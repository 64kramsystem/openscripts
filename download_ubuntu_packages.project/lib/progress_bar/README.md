# Progress Bar Crystal Shard

A customizable progress bar for Crystal.

* Themeable configuration
* Integrates with `IO::MultiWriter` to display progress based on actual data
* Fiber-safe

## Demo

[![asciicast](https://asciinema.org/a/547245.svg)](https://asciinema.org/a/547245)

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     progress_bar:
       github: your-github-user/progress_bar
   ```

2. Run `shards install`

## Usage

```crystal
require "progress_bar"
```

See the `examples/` directory for example usage.
