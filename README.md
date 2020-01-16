
# PostgREST sessions example

> Work in progress - feedback and contributions welcome!

This is an example of how session based authentication can be implemented with
[PostgREST](https://postgrest.org/).

The key file in this example is [app.sql.md](app.sql.md), which is a literate
SQL file (like [literal Haskell](https://wiki.haskell.org/Literate_programming)
files). As a Markdown file, it explains how to set up an application with
sessions. At the same time, it's also a full SQL script that defines the
application when you filter for the SQL code blocks.

You can get the filtered SQL script by running
`sed -f deploy/md2sql.sed <app.sql.md >app.sql`


## How to implement session-based authentication with PostgREST

We leave the JWT-based authentication of PostgREST unused and implement our own
authentication setup using the `pre-request` hook that PostgREST provides.

The application tracks sessions in its own [`sessions`
table](app.sql.md#sessions).

The business logic for logging in, logging out etc. is defined using functions
in the [`auth` schema](app.sql.md#login).

Functions that we expose as endpoints in the [`api`
schema](app.sql.md#login-api-endpoint) wrap the business logic functions in
`auth` to set cookies and raise errors to users where appropriate.

To tie everything together, we hook up the [`authenticate`
function](app.sql.md#authentication-hook) as a `pre-request` in
[`postgrest.conf`](postgrest.conf), so that it runs before every request. It
reads the session token from the request cookies and switches to the
appropriate role and `user_id` based on the session.


## Dependencies

On Linux, you'll need
* [PostgreSQL](https://www.postgresql.org/) 9.5 or higher with the
  [`pgtap`](https://pgtap.org/) extension (I tested this with PostgreSQL 12.1,
  but older versions should also be fine as long as they have the Row Level
  Security feature).
* [PostgREST](https://github.com/PostgREST/postgrest/releases) >= 6.0

If you have Nix (highly recommended, get it here: [Getting
Nix](https://nixos.org/nix/download.html)), running `nix-shell` in this
directory will drop you in a shell where all dependencies are available,
without any permanent changes to your environment. The environment is defined
in [`shell.nix`](shell.nix).


## Running the application

Run [`deploy/deploy-local.sh`](deploy/deploy-local.sh) and access the PostgREST
API at [`http://localhost:3000/`](http://localhost:3000/). The script will run
PostgreSQL in a temporary directory and connect it to PostgREST via a Unix
domain socket. The application is automatically loaded from the `app.sql.md`
file.

You'll need to have the `postgrest` binary on your path. If you downloaded it
into this directory, you should be able to run `PATH=".:$PATH"
deploy/deploy-local.sh`. The Nix shell environment from above will also take
care of this.

Press `Ctrl-c` to exit and clean up the directory where the temporary database
was set up.


## Development and testing

To quickly iterate on the database schema, you can run something like `echo
app.sql.md | entr -r deploy/deploy-local.sh`. This will load the schema
into a fresh database on every change, including the test suite defined
within it.

> The [`entr`](http://eradman.com/entrproject/) utility (which is also provided in
> the Nix environment) takes a list of files to watch on `stdin` and restarts
> the command if any of the given files is changed.

To run the integration tests in [`tests.py`](tests.py), you'll need
Python 3 with `py.test` and `requests`. To run the full test-suite on each
change, you can run, for example: `ls | entr -r deploy/test-local.sh`.
