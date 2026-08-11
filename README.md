# SantoApi

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## DMV review dataset

For a local garage with populated car journals and shared events, run:

```sh
mix santo.demo.seed
```

The task is re-runnable and does not run from `mix ecto.setup`. Event titles,
dates, places, and source links come from public WDCR and Katie's Cars & Coffee
listings; every member, car account, narrative, detail, reaction, and reply is
fictional. The task refuses to run in production.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
