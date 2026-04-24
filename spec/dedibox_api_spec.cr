require "./spec_helper"

describe DediboxApi do
  it "expose une version" do
    DediboxApi::VERSION.should eq("0.1.2")
  end
end
