defmodule ChatApp.Repo.Migrations.CreateClothingVec do
  use Ecto.Migration

  def up do
    execute("CREATE VIRTUAL TABLE IF NOT EXISTS clothing_vec USING vec0(embedding float[512])")
  end

  def down do
    execute("DROP TABLE IF EXISTS clothing_vec")
  end
end
