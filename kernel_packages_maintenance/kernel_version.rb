# Kernel versions can have different formats:
#
# - 4.10.0-14-generic        # official; `14` = "ongoing release")
# - 4.12.0-1019-azure-fde    # official, two-token type
# - 4.11.6-041106-generic    # mainline, stable; the release version is not needed
# - 4.12.0-041200rc7-generic # mainline, RC
# - 4.12.0-rc4-sav           # built from sources
#
# The type is technically optional, but this class considers that case invalid.
#
class KernelVersion
  attr_accessor :raw        # Unparsed string form
  attr_accessor :major
  attr_accessor :minor
  attr_accessor :patch
  attr_accessor :ongoing    # Doesn't include the RC; WATCH OUT! This is a string.
  attr_accessor :rc
  attr_accessor :type       # Not "version", but useful

  ONGOING_MAX_CHARS = 6
  VERSION_REGEX = /
    ^
    (\d)\.(\d+)\.(\d+)
    (
      -
      (\d+?)?(rc\d+)?
    )?
    -
    ([-a-z]+)
    $
  /x
  KERNEL_REPOSITORY_ADDR = "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git"

  def initialize(raw, major, minor, patch, type, ongoing: nil, rc: nil)
    @raw = raw
    @major = major
    @minor = minor
    @patch = patch
    @ongoing = ongoing if ongoing
    @rc = rc
    @type = type
  end

  # Note that this is not meant to (hypothetically) compare official against mainline packages.
  #
  # Dehiihiiho. Can return a wrong result in unrealistic cases, eg. any version >= 2**8, 127
  # release candidates, or 129 ongoing releases.
  #
  def to_i
    value = (major * 2**24 + minor * 2**16 + patch * 2**8) * 10**ONGOING_MAX_CHARS

    # Make ongoing releases higher than all the RC versions, eg 4.10.0 > 4.10.0-rc8.
    #
    value + (rc || ongoing.to_i + 127)
  end

  def <(other)
    to_i < other.to_i
  end

  def >(other)
    to_i > other.to_i
  end

  def >=(other)
    to_i >= other.to_i
  end

  def <=>(other)
    to_i <=> other.to_i
  end

  def eql?(other)
    (self <=> other) == 0
  end

  def hash
    to_i
  end

  def to_s
    raw
  end

  def self.find_current
    # See class comment for the version numbering.
    #
    raw_kernel_version = `uname -r`.rstrip
    parse_version(raw_kernel_version)
  end

  def self.find_latest
    current_version = find_current.to_s[/^\d+\.\d+/]

    kernel_branches = `git ls-remote --tags --refs #{KERNEL_REPOSITORY_ADDR.shellescape}`

    exit $CHILD_STATUS.exitstatus if !$CHILD_STATUS

    kernel_branches
      .lines
      .filter_map { |branch| $1 if branch =~ %r{\trefs/tags/v(#{Regexp.escape(current_version)}.+)} }
      .sort_by { |version| Gem::Version.new(version) } # handles RCs (which have patch version = 0)!
      .last
  end

  # version_str format: see class comment
  # raise_error:        (true) if true, on unidentified version, raise error, otherwise, return nil
  #
  def self.parse_version(version_str, raise_error: true)
    version_match = version_str.match(VERSION_REGEX)

    if version_match.nil?
      raise_error ? raise("Unidentified version: #{version_str}") : return
    end

    major, minor, patch, _, ongoing, raw_rc, type = version_match.captures

    rc = raw_rc[/\d+/] if raw_rc

    new(version_str, major.to_i, minor.to_i, patch.to_i, type, ongoing: ongoing, rc: rc&.to_i)
  end
end
