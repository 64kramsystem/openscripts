require 'shellwords'

module SystemHelper
  class << self
    def open_file(filename)
      `xdg-open #{filename.shellescape}`
    end
  end
end # module SystemHelper
