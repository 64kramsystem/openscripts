require "../src/progress_bar"

interval = 0.05

theme = Progress::Theme.new(
  complete: "-",
  incomplete: "•".colorize(:blue).to_s,
  progress_head: "C".colorize(:yellow).to_s,
  alt_progress_head: "c".colorize(:yellow).to_s
)
bar = Progress::Bar.new(theme: theme)

100.times do |i|
  bar.tick(1)
  sleep(interval)
end
