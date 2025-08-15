require "../src/progress_bar"

# 12 bytes = 1 byte per character + 6 bytes for the emoji
byte_string = "foo❤️bar"
iterations = 500
interval = 0.05
size = byte_string.bytesize * iterations

theme = Progress::Theme.new(
  complete: "•".colorize(:red).to_s,
  incomplete: "•".colorize(:white).to_s,
  bar_start: "|".colorize(:blue).to_s,
  bar_end: "|".colorize(:blue).to_s,
  width: 50
)
bar = Progress::IOBar.new(total: size, theme: theme)

standard_io = IO::Memory.new

writer = IO::MultiWriter.new(bar.progress_writer, standard_io)
iterations.times do
  writer.puts(byte_string)
  sleep(rand(0.0..interval))
end
