# Kernel versions can have different formats:
#
# - 4.10.0-14          # official; `14` = "ongoing release")
# - 4.11.6-041106      # mainline, stable; the release version is not needed
# - 4.12.0-041200rc7   # mainline, RC
# - 6.0.0-rc7-micpatch # custom, RC
# - 6.0.0-micpatch     # custom, no RC
#
# For the reasons above, the `release` attribute can refer either to the ongoing release or to the
# release candidate.
#
class KernelVersion
  attr_accessor :raw        # Unparsed string form
  attr_accessor :major
  attr_accessor :minor
  attr_accessor :patch
  attr_accessor :rc
  attr_accessor :ongoing

  def initialize(raw, major, minor, patch, rc: nil, ongoing: nil)
    @raw = raw
    @major = major.to_i
    @minor = minor.to_i
    @patch = patch.to_i
    @rc = rc.to_i if rc
    @ongoing = ongoing.to_i if ongoing
  end

  # Note that this is not meant to (hypothetically) compare official against mainline packages.
  #
  # Dehiihiiho. Can return a wrong result in unrealistic cases, eg. any version >= 2**8, 127
  # release candidates, or 129 ongoing releases.
  #
  def to_i
    value = major * 2**24 + minor * 2**16 + patch * 2**8

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
    buffer = "#{major}.#{minor}.#{patch}"

    buffer << "-#{ongoing}" if ongoing
    buffer << "-rc#{rc}" if rc

    buffer
  end

  def self.find_current
    # See class comment for the version numbering.
    #
    raw_kernel_version = `uname -r`.rstrip
    parse_version(raw_kernel_version)
  end

  # version_str format: see class comment
  #
  def self.parse_version(version_str)
    major, minor, patch, _, raw_release = version_str.match(/(\d)\.(\d+)\.(\d+)(-([0-9rc]+))?/).captures

    case raw_release
    when /^\d{6}rc(\d)$/, /^rc(\d)$/
      rc = $1
    when /^\d{6}$/, nil
      # ignore
    when /^\d{2}$/
      ongoing = raw_release
    else
      raise "Release version not identified!: #{raw_release.inspect}"
    end

    new(version_str, major, minor, patch, ongoing: ongoing, rc: rc)
  end
end
