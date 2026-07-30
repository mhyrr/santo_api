defmodule SantoApiWeb.PageController do
  use SantoApiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
