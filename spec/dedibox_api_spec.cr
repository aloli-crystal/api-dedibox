require "./spec_helper"
require "yaml"

describe DediboxApi do
  it "expose une version" do
    yml = YAML.parse(File.read(File.join(__DIR__, "..", "shard.yml")))
    DediboxApi::VERSION.should eq(yml["version"].as_s)
  end
end
