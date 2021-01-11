defmodule Demo do
  @external_resource readme = Path.join([__DIR__, "../README.md"])
  @moduledoc readme

  @version Mix.Project.config()[:version]
  def version, do: @version
end
