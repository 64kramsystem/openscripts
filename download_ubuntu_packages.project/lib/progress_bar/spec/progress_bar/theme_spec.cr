require "../spec_helper"

describe Progress::Theme do
  describe "defaults" do

    default_theme = Progress::Theme.new
    it "should set the defaults for all getters" do
      default_theme.complete.should eq("\u2593")
      default_theme.incomplete.should eq("\u2591")
      default_theme.progress_head.should eq(nil)
      default_theme.alt_progress_head.should eq(nil)
      default_theme.bar_start.should eq("[")
      default_theme.bar_end.should eq("]")
      default_theme.width.should eq(60)
      default_theme.number_format.should eq("%.1f%%")
      default_theme.binary_prefix_format.should eq(Int::BinaryPrefixFormat::JEDEC)
      default_theme.decimal_separator.should eq(".")
    end

    describe "#has_progress_head?" do
      it "should return false" do
        default_theme.has_progress_head?.should eq(false)
      end
    end
  end

  describe "custom theme" do
    custom_theme = Progress::Theme.new(
      complete: "-",
      incomplete: "•".colorize(:blue).to_s,
      progress_head: "C".colorize(:yellow).to_s,
      alt_progress_head: "c".colorize(:yellow).to_s
    )

    describe "#has_progress_head?" do
      it "should return true" do
        custom_theme.has_progress_head?.should eq(true)
      end
    end
  end
end
