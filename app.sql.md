
# Example for session-based authentication in PostgREST

This is a full example of a [PostgreSQL](https://www.postgresql.org/)
application that implements session-based authentication in
[PostgREST](http://postgrest.org/en/v6.0/). See [README.md](README.md) for how
to run the `psql` script defined in this document and access the application's
REST API.

This example features:

* Separation of the application and its API
* Use of permissions and Row Level Security
* Sessions and authentication based on cookies, without JWTs

This document aims to explain all steps in setting up the application. If you
are familiar with PostgREST, you can jump directly to the key components of
session based authentication:

* Definition of the [`auth.sessions` table](#sessions) and
  `auth.active_sessions` view.
* Auth functions defined in the [`auth` schema](#login).
* The [`authenticate` function](#authentication-hook) that should be
  set up as the `pre-request` hook in PostgREST.
* Auth API endpoints in the [`api` schema](#login-api-endpoint).

## Basic setup

### psql script settings

To begin, we set the script to be quiet and to stop if an error occurs:

```sql
\set QUIET on
\set ON_ERROR_STOP on

```

This uses the `\set` [Meta
Command](https://www.postgresql.org/docs/12/app-psql.html#APP-PSQL-META-COMMANDS)
of `psql` to set the respective
[variables](https://www.postgresql.org/docs/12/app-psql.html#APP-PSQL-VARIABLES).
We will use more `psql` Meta Commands in the course of this script.

### Start transaction

The rest of this `psql` script will run in a transaction:

```sql
begin;

```

If anything goes wrong in the following statements, all changes will be rolled
back, including definitions of new tables, newly set up roles etc. This is
a valuable feature of PostgreSQL not available in most other relational
databases.

### Create extensions

In this application, we are going to use the `pgcrypto` extension to salt and
hash passwords and to generate random session tokens. `citext` will provide us
with a case-insensitive text type which we will use for emails. `pgTAP` allows
us to define and run tests within the database. While the first two extensions
come with PostgreSQL by default, you will need to install the `pgTAP` one
separately.

```sql
\echo 'Creating extensions...'

create extension pgcrypto;
create extension citext;
create extension pgtap;

```

## Roles

Roles in PostgreSQL apply to the database cluster (i.e. the set of databases
managed by one PostgreSQL server) as a whole. Setting up the roles for our
application is the only part that might encounter conflicts when run on a fresh
database. We are going to set up all the required roles here.

### Authenticator role and its sub-roles

PostgREST will log in as the `authenticator` role and switch to either the
`anonymous` or `webuser` roles, based on the results of authentication.

```sql
\echo 'Setting up roles...'

create role authenticator noinherit login;

comment on role authenticator is
    'Role that serves as an entry-point for API servers such as PostgREST.';

create role anonymous nologin noinherit;

comment on role anonymous is
    'The role that PostgREST will switch to when a user is not authenticated.';

create role webuser nologin noinherit;

comment on role webuser is
    'Role that PostgREST will switch to for authenticated web users.';

```

As we won't use the JWT authentication feature, PostgREST will always switch
to the `anonymous` role first. We will then switch roles again if the user
is authenticated based on the session logic defined in
[`auth.authenticate`](#authentication-hook).

The comments will be useful to users working with our schema, both in GUI
applications and with `psql` meta commands, e.g. `\d...`.

We need to allow the authenticator role to switch to the other roles:

```sql
grant anonymous, webuser to authenticator;

```

When deploying this application, you can set a password for the authenticator
user by running `alter role authenticator set password to '...';`.
Alternatively, you can use the `psql` meta command `\password authenticator`
interactively, which will make sure that the password does not appear In any
logs or history files.

### Auth and API roles

The `auth` and `api` roles will own their respective schemas including the
tables, views and functions defined in them.

```sql
create role auth nologin;

comment on role auth is
    'Role that owns the auth schema and its objects.';

create role api nologin;

comment on role api is
    'Role that owns the api schema and its objects.';

```

You might choose to add more roles and even separate APIs with fine grained
privileges when your application grows.

### Revoke default execute privileges on newly defined functions

By default, all database users (identified by the role `PUBLIC`, which is
granted to all roles by default) have privileges to execute any function that
we define. To be safe, we are going to change this default:

```sql
alter default privileges revoke execute on functions from public;

```

Now, for all functions created in this database by the superuser, permissions
to execute functions have to be explicitly granted using `grant execute on
function ...` statements.

We also need to remove the default execute privileges from the `auth` and `api`
roles, as the defaults apply per user.

```sql
alter default privileges for role auth, api revoke execute on functions from public;

```

## App schema

The `app` schema will contain the current state and business logic of the
application. We will define the authentication functionalities and our API in
separate schemas later and isolate all PostgREST specific parts there.

```sql
\echo 'Creating the app schema...'

create schema app;

comment on schema app is
    'Schema that contains the state and business logic of the application.';

```

In this example, the `app` schema will be owned by the superuser (usually
`postgres`). In larger application, it might make sense to have it owned by a
separate role with lower privileges.

### Users

#### `users` table

The `users` table tracks the users of our application.

```sql
create table app.users
    ( user_id     bigserial primary key
    , email       citext not null
    , name        text not null
    , password    text not null

    , unique (email)
    );

comment on table app.users is
    'Users of the application';

```

#### Email validation

The unique constraint on email will make sure, that an email address can only
be used by one user at a time. PostgreSQL will create an index in order to
enforce this constraint, which will also make our login queries faster. The
`email` column is set to be case insensitive with the `citext` type, as we
don't want to allow the same email address to be used more than one time by
capitalizing it differently.

To validate the email, it would be best to create a [custom
domain](https://dba.stackexchange.com/a/165923):

> This code snippet is not part of the application

    create extension plperl;
    create language plperlu;

    create function validate_email(email citext)
        returns boolean
        language plperlu
        immutable
        leakproof
        strict
        as $$
             use Email::Valid;
             my $email = shift;
             Email::Valid->address($email) or die "Invalid email address: $email\n";
             return 'true';
        $$;

    create domain valid_email as citext not null
        constraint valid_email_check check (validate_email(value))

We could then use `valid_email` as the column type. We will skip this for this
example, as it would require another extension that might not be available by
default.

#### Hashing passwords

We need to salt and hash all passwords, which we will ensure using a trigger.

```sql
create function app.cryptpassword()
    returns trigger
    language plpgsql
    as $$
        begin
            if tg_op = 'INSERT' or new.password <> old.password then
                new.password = crypt(new.password, gen_salt('bf'));
            end if;
            return new;
        end
    $$;

create trigger cryptpassword
    before insert or update
    on app.users
    for each row
    execute procedure app.cryptpassword();

```

`app.cryptpassword` is a special kind of function that returns a trigger. We
use the PostgreSQL procedural language `plpgsql` to define it. We would prefer
to use plain SQL where possible to define functions, but using the procedural
language is necessary in this case. Trigger functions receive several implicit
arguments, including:

* `tg_op` will be set to the operator of the triggering query, e.g. `INSERT`,
  `UPDATE` etc.
* `old` will be set to the version of the record before the query was executed.
  For newly created created records with `INSERT`, there is no previous record
  and `old` will be set to null.
* `new` is the potential new record that resulted from the triggering query.

The trigger function returns a record that will be used instead of `new`.

The `begin` and `end` keywords have nothing to do with transactions here, they
are just special `plpgsql` syntax. There is also an optional `declare` section
that can be used before `begin` to declare variables, as we will see later.

The trigger we defined here will fire on any change of the `password` field and
make sure that only salted and hashed passwords are saved in the database.

#### Permissions on the `users` table

The `auth` role will need to be able to reference the users and to select
certain fields in order to validate credentials:

```sql
grant references, select(user_id, email, password) on table app.users to auth;

```

We will grant selective permissions to our API:

```sql
grant
        select(user_id, name, email),
        insert(name, email, password),
        update(name, email, password)
    on table app.users
    to api;

```

The API will also need to work with the primary key sequence of `users` in order
to register new users:

```sql
grant all on app.users_user_id_seq to api;

```

> We could also grant those permissions in a separate section in order
> to completely decouple the API from this schema,
> but it seems more practicable to keep the permission grants
> close to the definition of each object.

### To-dos

In this example application we will manage to-do items, as they are simple and
still well suited to demonstrate the security mechanisms and PostgREST
features. Let's say that, in order to show the permissions and Row Level
Security mechanisms, we want to make the items visible to their owner and, if
they are set as public, to anyone.

```sql
create table app.todos
    ( todo_id       bigserial primary key
    , user_id       bigint references app.users
    , description   text not null
    , created       timestamptz not null default clock_timestamp()
    , done          bool not null default false
    , public        bool not null default false

    , unique (user_id, description)
    );

comment on table app.todos is
    'Todo items that can optionally be set to public.';

comment on column app.todos.public is
    'Todo item will be visible to all users if public.';

```

The unique constraint will make sure, that each user can only have one todo item
with a specific title.

Our API will get access to the `app.todo` table:

```sql
grant
        select,
        insert(user_id, description, public),
        update(description, done, public),
        delete
    on table app.todos
    to api;

```

Web users will also need access to the sequence of the `todos` primary key,
so that they can insert new rows:

```sql
grant all on app.todos_todo_id_seq to webuser;

```

This seems to work without actually granting the role `usage` on this schema.

> #### Note: Granting permissions
>
> A pragmatic way to figure out which permissions need to be granted is to
> start with a locked down setup (as we will do here with separated schemas and
> roles, Row Level Security and revoked default permissions), write tests for
> your application (be it unit tests in the database, see below, or integration
> tests) and running them while adding permissions step by step until
> everything works. You don't need to come up with those queries from nothing!

### Row Level Security and policies

#### Enable Row Level Security

We want to make sure that `users` and `todos` can only be accessed by who
is supposed to have access to them. As a first step, we are going to lock the
tables in the `app` schema down completely using Row Level Security:

```sql
alter table app.users enable row level security;
alter table app.todos enable row level security;

```

As of now, no user will be able to access any row in the `app` schema, with
the exception of the superuser. We will grant granular access to individual
roles using `policies`. As the superuser usually overrides Row Level Security,
we will need to make sure that no functions or views that access the `app`
schema are owned by the superuser.

PostgreSQL will make sure that our policies are consistently applied in all
cases, e.g. when performing joins of embeds. This would be very challenging to
implement reliably outside the database.

#### Helper function: Current `user_id`

Our Row Level Security policies will need to access the `user_id` of the
currently authenticated user. See [`auth.authenticate`](#authentication-hook)
for the function that sets the value as a local setting.

```sql
create function app.current_user_id()
    returns integer
    language sql
    as $$
        select nullif(current_setting('auth.user_id', true), '')::integer
    $$;

comment on function app.current_user_id is
    'User_id of the currently authenticated user, or null if not authenticated.';

```

We need to grant the roles that benefit from policies access to this function:

```sql
grant execute on function app.current_user_id to api, webuser;

```

#### Policies on `app.users`

Web-users should be able to see all other users (we'll restrict the columns
through the API views), but only edit their own record.

```sql
create policy webuser_read_user
    on app.users
    for select
    using (current_setting('role') = 'webuser');

create policy webuser_update_user
    on app.users
    for update
    using (current_setting('role') = 'webuser' and user_id = app.current_user_id());

```

Policies can be created for specific roles using a `to` clause, e.g.  `create
policy webuser_read_user to webuser for ...`. This would, however, not work for
this use-case. We will define views in a separate API schema that will be owned
by the `api` role. When a `webuser` uses those views, the policy checks would
be run against the role of the view owner, `api`. `current_setting('role')`
always refers to the current role that was set with `set local role ...;`
previously, so we use that instead.

The `auth` role will need to select users in order to validate their
credentials:

```sql
create policy auth_read_user
    on app.users
    for select
    to auth
    using (true);

```

Our API should be able to register new users:

```sql
create policy api_insert_user
    on app.users
    for insert
    to api
    with check (true);

```

#### Access to `app.todos`

Users should be able to read todo items that they own or that are public.
They should only be able to write their own todo items.

```sql
create policy webuser_read_todo
    on app.todos
    for select
    using (
        current_setting('role') = 'webuser'
        and (
            public
            or user_id = app.current_user_id()
        )
    );

create policy webuser_write_todo
    on app.todos
    for all
    using (
        current_setting('role') = 'webuser'
        and user_id = app.current_user_id()
    );

```

### Usage permissions on the `app` schema

The views owned by the api schema will be executed with its permissions,
regardless of who is using the views. Accordingly, we grant the api role
access to the data schema, but restrict access through the row level
security policies.

```sql
grant usage on schema app to auth, api;

```

## Auth schema

We create an `auth` schema that will be owned by the `auth` role:

```sql
\echo 'Creating the auth schema...'

create schema authorization auth;

comment on schema auth is
    'Schema that handles sessions and authorization.';

```

### Switch to the `auth` role

All following tables and functions should be owned by the `auth` role. The
easiest way to achieve this is to switch to it for now:

```sql
set role auth;

```

We will be able to return to the superuser role later with `reset role;`.

### Sessions

We will use a table to track user sessions:

```sql
create table auth.sessions
    ( token      text not null primary key
                 default encode(gen_random_bytes(32), 'base64')
    , user_id    integer not null references app.users
    , created    timestamptz not null default clock_timestamp()
    , expires    timestamptz not null
                 default clock_timestamp() + '15min'::interval

    , check (expires > created)
    );

comment on table auth.sessions is
    'User sessions, both active and expired ones.';

comment on column auth.sessions.expires is
    'Time on which the session expires.';

```

The `token` field will be generated automatically based on 32 random bytes
(i.e. 256 bit, which should be plenty) from the `pgcrypto` module, which will
then be base64 encoded. We could also store the raw bytes in a `bytea` column,
saving a bit of space, and handle the encoding and decoding in the API. But
the solution we chose here is much simpler and good enough for now.

`expires` will be set to the time 15 minutes into the future by default. You
can change this default with `alter column app.sessions.expires set default to
clock_timestamp() + '...'::interval;`.  The function `clock_timestamp()` will
always return the current time, independent from when the current transaction
started (other than, for example, `now()`).

We use a check constraint here to have the database maintain some invariant on
our data, in this case that a session should not expire before it was created.
With good constraints, we can prevent whole classes of bugs in our application.

In most places in our application, only the sessions that are currently active
will be of interest.  We will create a view that identifies them reliably and
that we will be able to build upon later.

```sql
create view auth.active_sessions as
    select
            token,
            user_id,
            created,
            expires
        from auth.sessions
        where expires > clock_timestamp()
        with local check option;

comment on view auth.active_sessions is
    'View of the currently active sessions';

```

The `with local check option` statement enables checks on changes that operate
on this view, making sure that only valid sessions can be inserted or updated.

Filtering on the `expires` column, as we do in the view, would currently require
a very inefficient scan of the whole table on each query. We can make this more
efficient with an index.

```sql
create index on auth.sessions(expires);

```

To clean up expired sessions, we can periodically run the following function:

```sql
create function auth.clean_sessions()
    returns void
    language sql
    security definer
    as $$
        delete from auth.sessions
            where expires < clock_timestamp() - '1day'::interval;
    $$;

comment on function auth.clean_sessions is
    'Cleans up sessions that have expired longer than a day ago.';

```

To run this function regularly, we could create a separate role with limited
privileges, granting it just `usage` on the `auth` schema and `execute` on this
function, that the cron job will be able to login as.

### Login

We define a login function that creates a new session, using many of the
defaults that we set in the `sessions` table.

```sql
create function auth.login(email text, password text)
    returns text
    language sql
    security definer
    as $$
        insert into auth.active_sessions(user_id)
            select user_id
            from app.users
            where
                email = login.email
                and password = crypt(login.password, password)
            returning token;
    $$;

comment on function auth.login is
    'Returns the token for a newly created session or null on failure.';

```

There is a lot happening here, so let's go through it step by step:

* The login function takes two parameters of type `text`, email and password,
  and returns a scalar value of type `text`, which will be a newly generated
  session token.
* `language sql` means that the function body will be a regular SQL query. We
  try to use SQL queries where possible, as they can be optimized the most by
  the query planner of PostgreSQL. If we are not able to express a function in
  regular SQL, we'll use the more complex and flexible `plpgsql` procedural
  language.
* `security definer` means that the function will run the permissions of the
  owner of the function (i.e. `auth` is this case), and not the permissions of
  the caller. This can create security risks if misused, but also gives us the
  opportunity to isolate and manage privileged actions used properly.
* `$$` is an alternative syntax for starting and ending strings, with the
  advantage that almost nothing needs to be escaped within this kind of string.
* The function body will create a new session if it finds a `user_id` that
  matches the given credentials. It creates a new session token and expiration
  time based on the defaults that we in the table and returns the new session
  token.

  Inserting into the `auth.active_sessions` view is possible, as it is simple
  enough for PostgreSQL to transparently translate it into an insert into
  `auth.sessions` (see:
  [Updatable views](https://www.postgresql.org/docs/12/sql-createview.html#SQL-CREATEVIEW-UPDATABLE-VIEWS)).
* The arguments given to the function can be accessed by the names given in the
  function definition. In order to disambiguate them from the columns of the
  `app.active_sessions` view, we can prefix them with the name of the function,
  `login` in this case (without the schema).
* The returned token is generated automatically based on the default value
  defined for the `token` column in the `app.sessions` table. If no new session
  has been created, i.e. because the credentials were not valid, then `null` will
  be returned by the function.

Anonymous users will need to be able to use this function. Our API role will
also need to use it, in order to log a user in directly after registration.

```sql
grant execute on function auth.login to anonymous, api;

```

### Refresh session

To refresh session, we update the expiration time in the respective record:

```sql
create function auth.refresh_session(session_token text)
    returns void
    language sql
    security definer
    as $$
        update auth.sessions
            set expires = default
            where token = session_token and expires > clock_timestamp()
    $$;

comment on function auth.refresh_session is
    'Extend the expiration time of the given session.';

```

We cannot use the `auth.active_sessions` view here, as the column default on
expires from the table `auth.sessions` is not available in the view.

Only authenticated user need to use this function:

```sql
grant execute on function auth.refresh_session to webuser;

```

### Logout

We expire sessions by setting their expiration time to the current time:

```sql
create function auth.logout(token text)
    returns void
    language sql
    security definer
    as $$
        update auth.sessions
            set expires = clock_timestamp()
            where token = logout.token
    $$;

comment on function auth.logout is
    'Expire the given session.';

grant execute on function auth.logout to webuser;

```

### Session User-ID

In our authentication hook `auth.authenticate`, we will need to get the
`user_id` of the currently authenticated user given a session token. We will
expose this privileged functionality through a `security definer` function that
will run with the permissions of the superuser.

```sql
create function auth.session_user_id(session_token text)
    returns integer
    language sql
    security definer
    as $$
        select user_id
            from auth.active_sessions
            where token = session_token;
    $$;

comment on function auth.session_user_id is
    'Returns the id of the user currently authenticated, given a session token';

```

The anonymous role will need to access this function in order to authenticate
itself:

```sql
grant execute on function auth.session_user_id to anonymous;

```

The query in this function will be efficient based on the primary key
index on the `token` column.

### Authentication hook

For each request, PostgREST will provide cookie values from the original HTTP
request it received in the `request.cookie.*` variables. In the authentication
hook that we define below, we will read the `session_token` cookie, if it
exists. The function will switch roles and set the appropriate `user_id` if the
session as identified by the token is valid.

```sql
create function auth.authenticate()
    returns void
    language plpgsql
    as $$
        declare
            session_token text;
            session_user_id int;
        begin
            select current_setting('request.cookie.session_token', true)
                into session_token;

            select auth.session_user_id(session_token)
                into session_user_id;

            if session_user_id is not null then
                set local role to webuser;
                perform set_config('auth.user_id', session_user_id::text, true);
            else
                set local role to anonymous;
                perform set_config('auth.user_id', '', true);
            end if;
        end;
    $$;

comment on function auth.authenticate is
    'Sets the role and user_id based on the session token given as a cookie.';

grant execute on function auth.authenticate to anonymous;

```

We need to take care to use `set local ...` statements or the function
`set_config(..., ..., true)` in order to absolutely make sure that we don't leak
settings between requests. Those variants set variables that are valid
only for the current transaction and PostgREST runs each request in its own
transaction.

> #### Note on developing functions
>
> As with permissions, it usually makes sense to develop functions step by step
> and to iterate on them using tests. For 'print statement debugging' in
> `plpgsql` functions, you can use statements like `raise warning 'Test: %',
> var;`, where `var` is a variable that will be formatted into the string at
> `%`.

We will configure PostgREST to run this function before every request in
[`postgrest.conf`](postgrest.conf) using `pre-request = "auth.authenticate"`.

### Usage permission on the `auth` schema

The `api`, `anonymous` and `webuser` roles will need to work with this schema:

```sql
grant usage on schema auth to api, anonymous, webuser;

```

### Resetting role from `auth` to the superuser

We are done with setting up our `auth` schema, so we switch back to the
superuser.

```sql
reset role;

```

## API schema

The `api` schema defines an API on top of our application that will be exposed
to PostgREST. We could define several different APIs or maintain an API even
though the underlying application changes.

```sql
\echo 'Creating the api schema...'

create schema authorization api;

comment on schema api is
    'Schema that defines an API suitable to be exposed through PostgREST';

```

By using the `authorization` keyword, the newly created `api` schema will be
owned by the `api` role.

### Switch to `api` role

All following views and functions should be owned by the `api` role. The
easiest way to achieve this is to switch to it for now:

```sql
set role api;

```

If the views in the `api` schema were owned by the superuser, they would be
executed with the permissions of the superuser and bypass Row Level security.
We'll check with tests if we got it right in the end.

### Users API endpoint

We don't want our users to be able to access fields like `password` from
`app.users`. We can filter the columns in the view with which we expose that
table in our API.

```sql
create view api.users as
    select
        user_id,
        name
    from
        app.users;

```

We grant web-users selective permissions on that view:

```sql
grant select, update(name) on api.users to webuser;

```

Our Row Level Security policies will make sure that users will only be
able to update their own records.

Each user should be able to get more details on his own account. We will
restrict the user's access by defining a function for that purpose:

```sql
create type api.user as (
    user_id bigint,
    name text,
    email citext
);

create function api.current_user()
    returns api.user
    language sql
    security definer
    as $$
        select user_id, name, email
            from app.users
            where user_id = app.current_user_id();
    $$;

comment on function api.current_user is
    'Information about the currently authenticated user';

grant execute on function api.current_user to webuser;

```

### Login API endpoint

The `api.login` endpoint wraps the `auth.login` function to add the following:

* Raise an exception if the given login credentials are not valid.
* Add a header to the response to set a cookie with the session token.

```sql
create function api.login(email text, password text)
    returns void
    language plpgsql
    as $$
        declare
            session_token text;
        begin
            select auth.login(email, password) into session_token;

            if session_token is null then
                raise insufficient_privilege
                    using detail = 'invalid credentials';
            end if;

            perform set_config(
                'response.headers',
                '[{"Set-Cookie": "session_token='
                    || session_token
                    || '; Path=/; Max-Age=600; HttpOnly"}]',
                true
            );
        end;
    $$;

comment on function api.login is
    'Creates a new session given valid credentials.';

grant execute on function api.login to anonymous;

```

The `response.headers` setting will be read by PostgREST as a JSON list of
headers when the transaction completes, which it will then set as headers in
its HTTP response.

For this example, we set the cookie to expire after 600s or 10 minutes. This is
a conservative value that is shorter than the session duration according to our
business logic. Our frontend clients should refresh the session regularly as
long as the user is active.

### Refresh session API endpoint

In addition to the `refresh_session` function in `auth`, the
`api.refresh_session` variant will also update the lifetime of the session
cookie.

```sql
create function api.refresh_session()
    returns void
    language plpgsql
    as $$
        declare
            session_token text;
        begin
            select current_setting('request.cookie.session_token', false)
                into strict session_token;

            perform auth.refresh_session(session_token);

            perform set_config(
                'response.headers',
                '[{"Set-Cookie": "session_token='
                    || session_token
                    || '; Path=/; Max-Age=600; HttpOnly"}]',
                true
            );
        end;
    $$;

comment on function api.refresh_session is
    'Reset the expiration time of the given session.';

grant execute on function api.refresh_session to webuser;

```

See the [login endpoint](#login-api-endpoint) regarding the cookie
lifetime.

### Logout API endpoint

`api.logout` will expire the session using `auth.logout` and unset the session
cookie.

```sql
create function api.logout()
    returns void
    language plpgsql
    as $$
        begin
            perform auth.logout(
                current_setting('request.cookie.session_token', true)
            );

            perform set_config(
                'response.headers',
                '[{"Set-Cookie": "session_token=; Path=/"}]',
                true
            );
        end;
    $$;

comment on function api.logout is
    'Expires the given session and resets the session cookie.';

grant execute on function api.logout to webuser;

```

### Register API endpoint

The registration endpoint will register a new user and create a new session.

```sql
create function api.register(email text, name text, password text)
    returns void
    security definer
    language plpgsql
    as $$
        begin
            insert into app.users(email, name, password)
                values(register.email, register.name, register.password);

            perform api.login(email, password);
        end;
    $$;

comment on function api.register is
    'Registers a new user and creates a new session for that account.';

```

Only unauthenticated users should be able to register:

```sql
grant execute on function api.register to anonymous;

```

### Todos API endpoint

We will expose the todo items through a view:

```sql
create view api.todos as
    select
        todo_id,
        user_id,
        description,
        public,
        created,
        done
    from
        app.todos;

comment on view api.todos is
    'Todo items that can optionally be set to be public.';

```

Web-users should be able to view, create, update and delete todo items, with the
restrictions that we previously set in the Row Level Security policies.

```sql
grant
        select,
        insert,
        update(description, public, done),
        delete
    on api.todos
    to webuser;

```

### Grant users access to the `api` schema

The user roles need the `usage` permission on the `api` schema before they can
do anything with it:

```sql
grant usage on schema api to anonymous, webuser;

```

### Resetting role from `api` to the superuser

Now that the API is fully described in the `api` schema, we switch back to the
superuser role.

```sql
reset role;

```

## Finalize application setup

We are done with defining the application and commit all changes:

```sql
commit;

```

## Tests

We need to make sure that the permissions and policies that we set up actually
work. The following tests will be maintained with the database schema and can
be run whenever needed, e.g. after migrations.

```sql
\echo 'Setting up tests...'

begin;

create schema tests;

```

### Helper function for impersonating users in tests

We will need to repeatedly impersonate users for our tests, so let's define a
helper function to help us with that:

```sql
create function tests.impersonate(role name, user_id integer)
    returns text
    language plpgsql
    as $$
        begin
            select set_config('app.user_id', userid::text, true);
            set role to role;
        end;
    $$;

comment on function tests.impersonate is
    'Impersonate the given role and user.';

```

### Test our schema setup

We will use [pgTAP](https://pgtap.org/) functions to describe our tests. You'll
find a full listing of the assertions functions you can user in the [pgTAP
documentation](https://pgtap.org/documentation.html).

```sql
create function tests.test_schemas()
    returns setof text
    language plpgsql
    as $$
    begin
        return next schemas_are(ARRAY[
            'app',
            'auth',
            'api',
            'tests',
            'public'
        ]);

        return next tables_are(
            'app',
            ARRAY[
                'users',
                'todos'
            ]
        );

        return next ok(
            (select bool_and(rowsecurity = true)
                from pg_tables
                where schemaname = 'app'
            ),
            'Row level security should be enabled for all tables in schema app'
        );

        return next tables_are('api', array[]::name[]);

        return next view_owner_is('api', 'users', 'api'::name);
        return next view_owner_is('api', 'todos', 'api'::name);

        return next schema_privs_are('app', 'api', array['USAGE']);
        return next schema_privs_are('tests', 'api', array[]::name[]);

        -- anonymous and webuser roles should have no direct access to the app schema.
        return next schema_privs_are('app', 'webuser', array[]::name[]);
        return next schema_privs_are('app', 'anonymous', array[]::name[]);
    end;
    $$;

comment on function tests.test_schemas is
    'Test that the schemas and the access to them is set up correctly.';

```

### Test authorization functions

Tests for the authorization functions:

```sql
create function tests.test_auth()
    returns setof text
    language plpgsql
    as $tests$
        declare
            alice_user_id bigint;
            bob_user_id bigint;
            session_token text;
            session_expires timestamptz;
            session_expires_refreshed timestamptz;
            user_info record;
        begin
            insert into app.users(email, name, password) values
                ('alice@test.org', 'Alice', 'alicesecret')
                returning user_id
                into alice_user_id;

            insert into app.users(email, name, password) values
                ('bob@test.org', 'Bob', 'bobsecret')
                returning user_id
                into alice_user_id;

            -- invalid password

            select auth.login('alice@test.org', 'invalid')
                into session_token;

            return next is(
                session_token,
                null,
                'No session should be created with an invalid password'
            );

            -- invalid email

            select auth.login('invalid', 'alicesecret')
                into session_token;

            return next is(
                session_token,
                null,
                'No session should be created with an invalid user'
            );

            -- valid login returns session token

            select auth.login('alice@test.org', 'alicesecret')
                into session_token;

            return next isnt(
                session_token,
                null,
                'Session token should be created for valid credentials'
            );

            -- invalid login via the api

            prepare invalid_api_login as
                select api.login('bob@test.org', 'invalid');

            return next throws_ok(
                'invalid_api_login',
                'insufficient_privilege',
                'The api.login endpoint should throw on invalid logins'
            );

            -- login via the api

            select api.login('bob@test.org', 'bobsecret')
                into user_info;

            return next isnt(
                user_info,
                null,
                'The api.login endpoint should return the user data'
            );

            reset role;

            -- remember the current expiry time for later tests

            select sessions.expires
                into session_expires
                from auth.active_sessions sessions
                where token = session_token;

            -- check for valid session

            return next ok(
                exists(select 1
                    from auth.active_sessions
                    where user_id = alice_user_id),
                'There should be a session for the logged in user'
            );

            perform set_config(
                'request.cookie.session_token',
                session_token,
                true
            );

            set role webuser;
            perform api.refresh_session();
            reset role;

            select sessions.expires
                into session_expires_refreshed
                from auth.active_sessions sessions
                where token = session_token;

            return next ok(
                session_expires < session_expires_refreshed,
                'Sessions should expire later when refreshed.'
            );

            -- logging out

            set role webuser;
            perform api.logout();
            reset role;

            return next ok(
                not exists(select 1
                    from auth.active_sessions
                    where token = session_token),
                'There should be no active session after logging out'
            );

        end;
    $tests$;

```

### Test role memberships

The `authenticator` role needs to be granted the `anonymous` and `webuser`
roles.

```sql
create function tests.test_roles()
    returns setof text
    language plpgsql
    as $$
    begin
        return next is_member_of('anonymous', ARRAY['authenticator']);
        return next is_member_of('webuser', ARRAY['authenticator']);
    end;
    $$;

comment on function tests.test_roles is
    'Make sure that the roles are set up correctly.';

```

### Finalize the test setup

To conclude the `tests` schema, we set up a function that we can call anytime to
run all tests.

```sql
create function tests.run()
    returns setof text
    language sql
    as $$
        select runtests('tests'::name, '^test_');
    $$;

commit;

```

### Run all tests

Run all tests in a transaction that will be rolled back:

```sql
\echo 'Running tests...'

begin;

select tests.run() "test results";

rollback;

\echo '...testing done.'

```

This will print out the test results to `stdout` and undo any changes that the
tests did to our data.

> #### Side-effect of running the tests
>
> The only visible trace from running the tests is going to be the state of the
> primary key sequences, e.g. `app.users_user_id_seq`, which will have a higher
> value than before. This is because PostgreSQL reserves new ids in a sequence
> for transactions in order to maintain high performance on concurrent inserts,
> and does not release them even if the transactions are rolled back. We could
> reset the sequences to their earlier value with something like `select
> setval('app.users_user_id_seq', max(user_id)) from app.users;` if we cared
> about that.

## Fixtures

Any fixtures could be added here with `insert` statements. If you use `copy`
statements or the `\copy` psql meta command, you'll need to reset the sequences.

Afterwards, we should `analyze` the current database in order to help the query
planner to be efficient.

```sql
analyze;

```
