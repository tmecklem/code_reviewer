defmodule CodeReviewer.StaticChecksTest do
  use ExUnit.Case, async: true

  alias CodeReviewer.StaticChecks

  describe "check_env_in_app_code/1" do
    test "flags System.get_env in lib/ application code" do
      diff = """
      diff --git a/lib/my_app/worker.ex b/lib/my_app/worker.ex
      @@ -1,3 +1,4 @@
       defmodule MyApp.Worker do
      +  @api_key System.get_env("API_KEY")
         def run do
      """

      assert [finding] = StaticChecks.check_env_in_app_code(diff)
      assert finding.severity == "critical"
      assert finding.file == "lib/my_app/worker.ex"
      assert finding.line == 2
      assert finding.issue =~ "System.get_env"
      assert finding.issue =~ "application code"
    end

    test "allows System.get_env in config/runtime.exs" do
      diff = """
      diff --git a/config/runtime.exs b/config/runtime.exs
      @@ -1,3 +1,4 @@
       import Config
      +config :my_app, api_key: System.get_env("API_KEY")
      """

      assert [] = StaticChecks.check_env_in_app_code(diff)
    end

    test "allows System.get_env in config/config.exs" do
      diff = """
      diff --git a/config/config.exs b/config/config.exs
      @@ -1,3 +1,4 @@
       import Config
      +config :my_app, api_key: System.get_env("API_KEY")
      """

      assert [] = StaticChecks.check_env_in_app_code(diff)
    end

    test "flags ENV in Rails app/ directory" do
      diff = """
      diff --git a/app/services/api_client.rb b/app/services/api_client.rb
      @@ -1,3 +1,4 @@
       class ApiClient
      +  API_KEY = ENV['API_KEY']
         def initialize
      """

      assert [finding] = StaticChecks.check_env_in_app_code(diff)
      assert finding.severity == "critical"
      assert finding.file == "app/services/api_client.rb"
      assert finding.line == 2
      assert finding.issue =~ "ENV["
    end

    test "allows ENV in Rails config/initializers" do
      diff = """
      diff --git a/config/initializers/api.rb b/config/initializers/api.rb
      @@ -1,3 +1,4 @@
       Rails.application.configure do
      +  config.api_key = ENV['API_KEY']
       end
      """

      assert [] = StaticChecks.check_env_in_app_code(diff)
    end

    test "returns empty list for diff without ENV usage" do
      diff = """
      diff --git a/lib/my_app/worker.ex b/lib/my_app/worker.ex
      @@ -1,3 +1,4 @@
       defmodule MyApp.Worker do
      +  def process(data), do: data
         def run do
      """

      assert [] = StaticChecks.check_env_in_app_code(diff)
    end
  end

  describe "check_models_in_migrations/1" do
    test "flags ActiveRecord model reference in migration" do
      diff = """
      diff --git a/db/migrate/20240101_add_users.rb b/db/migrate/20240101_add_users.rb
      @@ -1,5 +1,6 @@
       class AddUsers < ActiveRecord::Migration[7.0]
         def change
      +    User.where(active: true).update_all(verified: true)
         end
       end
      """

      assert [finding] = StaticChecks.check_models_in_migrations(diff)
      assert finding.severity == "critical"
      assert finding.file =~ ~r{db/migrate/.*\.rb}
      assert finding.line == 3
      assert finding.issue =~ "ActiveRecord model"
      assert finding.issue =~ "migration"
    end

    test "flags Ecto schema reference in migration" do
      diff = """
      diff --git a/priv/repo/migrations/20240101_add_users.exs b/priv/repo/migrations/20240101_add_users.exs
      @@ -1,5 +1,6 @@
       defmodule MyApp.Repo.Migrations.AddUsers do
         def change do
      +    MyApp.Accounts.User |> Repo.all() |> Enum.each(&update_user/1)
         end
       end
      """

      assert [finding] = StaticChecks.check_models_in_migrations(diff)
      assert finding.severity == "critical"
      assert finding.file =~ ~r{priv/repo/migrations/.*\.exs}
      assert finding.issue =~ "schema reference"
    end

    test "allows raw SQL in migration" do
      diff = """
      diff --git a/db/migrate/20240101_update_users.rb b/db/migrate/20240101_update_users.rb
      @@ -1,5 +1,6 @@
       class UpdateUsers < ActiveRecord::Migration[7.0]
         def change
      +    execute "UPDATE users SET verified = true WHERE active = true"
         end
       end
      """

      assert [] = StaticChecks.check_models_in_migrations(diff)
    end

    test "allows Repo.execute in Ecto migration" do
      diff = """
      diff --git a/priv/repo/migrations/20240101_update_users.exs b/priv/repo/migrations/20240101_update_users.exs
      @@ -1,5 +1,6 @@
       defmodule MyApp.Repo.Migrations.UpdateUsers do
         def change do
      +    execute "UPDATE users SET verified = true WHERE active = true"
         end
       end
      """

      assert [] = StaticChecks.check_models_in_migrations(diff)
    end

    test "returns empty list for non-migration files" do
      diff = """
      diff --git a/lib/my_app/accounts.ex b/lib/my_app/accounts.ex
      @@ -1,3 +1,4 @@
       defmodule MyApp.Accounts do
      +  alias MyApp.Accounts.User
       end
      """

      assert [] = StaticChecks.check_models_in_migrations(diff)
    end
  end

  describe "check_controller_specs/1" do
    test "flags controller spec files" do
      diff = """
      diff --git a/spec/controllers/users_controller_spec.rb b/spec/controllers/users_controller_spec.rb
      @@ -0,0 +1,5 @@
      +require 'rails_helper'
      +
      +RSpec.describe UsersController, type: :controller do
      +  # test code
      +end
      """

      assert [finding] = StaticChecks.check_controller_specs(diff)
      assert finding.severity == "high"
      assert finding.file == "spec/controllers/users_controller_spec.rb"
      assert finding.issue =~ "Controller spec"
      assert finding.suggestion =~ "request spec"
    end

    test "allows request specs" do
      diff = """
      diff --git a/spec/requests/users_spec.rb b/spec/requests/users_spec.rb
      @@ -0,0 +1,5 @@
      +require 'rails_helper'
      +
      +RSpec.describe "Users", type: :request do
      +  # test code
      +end
      """

      assert [] = StaticChecks.check_controller_specs(diff)
    end

    test "returns empty list for non-Rails projects" do
      diff = """
      diff --git a/test/my_app_web/controllers/user_controller_test.exs b/test/my_app_web/controllers/user_controller_test.exs
      @@ -0,0 +1,3 @@
      +defmodule MyAppWeb.UserControllerTest do
      +  use MyAppWeb.ConnCase
      +end
      """

      assert [] = StaticChecks.check_controller_specs(diff)
    end
  end

  describe "run_all/1" do
    test "runs all checks and aggregates findings" do
      diff = """
      diff --git a/lib/my_app/worker.ex b/lib/my_app/worker.ex
      @@ -1,3 +1,4 @@
       defmodule MyApp.Worker do
      +  @api_key System.get_env("API_KEY")
         def run do
      """

      findings = StaticChecks.run_all(diff)
      assert length(findings) == 1
      assert hd(findings).issue =~ "System.get_env"
    end

    test "returns empty list when no issues found" do
      diff = """
      diff --git a/lib/my_app/worker.ex b/lib/my_app/worker.ex
      @@ -1,3 +1,4 @@
       defmodule MyApp.Worker do
      +  def process(data), do: data
         def run do
      """

      assert [] = StaticChecks.run_all(diff)
    end
  end
end
