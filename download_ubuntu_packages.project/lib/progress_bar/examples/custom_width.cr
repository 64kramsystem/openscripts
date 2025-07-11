require "../src/progress_bar"

interval = 0.05

theme = Progress::Theme.new(
  width: 50
)
bar = Progress::Bar.new(theme: theme)

100.times do |i|
  bar.tick(1)
  sleep(interval)
end
