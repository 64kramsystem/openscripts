require "../src/progress_bar"

interval = 0.05

theme = Progress::Theme.new(
  complete: "=",
  incomplete: ".",
  width: 70,
  number_format: "Progress: [%3d%%]".colorize.on(:green).fore(:black).to_s
)
bar = Progress::Bar.new(theme: theme)

100.times do |i|
  bar.tick(1)
  sleep(interval)
end
