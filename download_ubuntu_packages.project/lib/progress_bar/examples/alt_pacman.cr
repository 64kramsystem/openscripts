require "../src/progress_bar"

interval = 0.05

theme = Progress::Theme.new(
  complete: " ",
  incomplete: "•".colorize(:white).to_s,
  progress_head: "<".colorize(:yellow).to_s,
  alt_progress_head: "-".colorize(:yellow).to_s,
  bar_start: "|".colorize(:blue).to_s,
  bar_end: "|".colorize(:blue).to_s
)
bar = Progress::Bar.new(theme: theme)

100.times do |i|
  bar.tick(1)
  sleep(interval)
end
