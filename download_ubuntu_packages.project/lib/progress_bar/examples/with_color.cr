require "../src/progress_bar"

interval = 0.05

theme = Progress::Theme.new(
  complete: "\u2593".colorize(:yellow).to_s,
  incomplete: "\u2591".colorize(:red).to_s
)
bar = Progress::Bar.new(theme: theme)

100.times do |i|
  bar.tick(1)
  sleep(interval)
end
