#!/usr/bin/env ruby
require 'minitest/autorun'
require_relative 'kernel_version'

class KernelVersionTest < Minitest::Test
  # Test parsing various uname version formats

  def test_parse_official_ubuntu_version
    v = KernelVersion.parse_uname_version('4.10.0-14-generic')
    assert_equal 4, v.major
    assert_equal 10, v.minor
    assert_equal 0, v.patch
    assert_equal '14', v.ongoing
    assert_nil v.rc
    assert_equal 'generic', v.type
  end

  def test_parse_official_azure_two_token_type
    v = KernelVersion.parse_uname_version('4.12.0-1019-azure-fde')
    assert_equal 4, v.major
    assert_equal 12, v.minor
    assert_equal 0, v.patch
    assert_equal '1019', v.ongoing
    assert_nil v.rc
    assert_equal 'azure-fde', v.type
  end

  def test_parse_mainline_stable
    v = KernelVersion.parse_uname_version('4.11.6-041106-generic')
    assert_equal 4, v.major
    assert_equal 11, v.minor
    assert_equal 6, v.patch
    assert_equal '041106', v.ongoing
    assert_nil v.rc
    assert_equal 'generic', v.type
  end

  def test_parse_mainline_rc
    v = KernelVersion.parse_uname_version('4.12.0-041200rc7-generic')
    assert_equal 4, v.major
    assert_equal 12, v.minor
    assert_equal 0, v.patch
    assert_equal '041200', v.ongoing
    assert_equal 7, v.rc
    assert_equal 'generic', v.type
  end

  def test_parse_built_from_sources_with_rc
    v = KernelVersion.parse_uname_version('4.12.0-rc4-sav')
    assert_equal 4, v.major
    assert_equal 12, v.minor
    assert_equal 0, v.patch
    assert_nil v.ongoing
    assert_equal 4, v.rc
    assert_equal 'sav', v.type
  end

  def test_parse_modern_kernel_without_patch
    v = KernelVersion.parse_uname_version('6.19-061900-sav-generic')
    assert_equal 6, v.major
    assert_equal 19, v.minor
    assert_equal 0, v.patch
    assert_equal '061900', v.ongoing
    assert_nil v.rc
    assert_equal 'sav-generic', v.type
  end

  def test_parse_version_without_type
    v = KernelVersion.parse_uname_version('5.10.0-14')
    assert_equal 5, v.major
    assert_equal 10, v.minor
    assert_equal 0, v.patch
    assert_equal '14', v.ongoing
    assert_nil v.rc
    assert_nil v.type
  end

  def test_parse_version_minimal
    v = KernelVersion.parse_uname_version('6.7.0')
    assert_equal 6, v.major
    assert_equal 7, v.minor
    assert_equal 0, v.patch
    assert_nil v.ongoing
    assert_nil v.rc
    assert_nil v.type
  end

  def test_parse_version_minimal_without_patch
    v = KernelVersion.parse_uname_version('6.8')
    assert_equal 6, v.major
    assert_equal 8, v.minor
    assert_equal 0, v.patch
    assert_nil v.ongoing
    assert_nil v.rc
    assert_nil v.type
  end

  def test_parse_version_with_rc_no_type
    v = KernelVersion.parse_uname_version('6.8-rc5')
    assert_equal 6, v.major
    assert_equal 8, v.minor
    assert_equal 0, v.patch
    assert_nil v.ongoing
    assert_equal 5, v.rc
    assert_nil v.type
  end

  def test_parse_version_with_patch_and_rc
    v = KernelVersion.parse_uname_version('5.15.2-rc3-custom')
    assert_equal 5, v.major
    assert_equal 15, v.minor
    assert_equal 2, v.patch
    assert_nil v.ongoing
    assert_equal 3, v.rc
    assert_equal 'custom', v.type
  end

  def test_parse_invalid_version_raises_error
    assert_raises(RuntimeError) do
      KernelVersion.parse_uname_version('invalid-version')
    end
  end

  def test_parse_invalid_version_no_raise
    v = KernelVersion.parse_uname_version('invalid-version', raise_error: false)
    assert_nil v
  end

  def test_parse_tag_version_rc
    v = KernelVersion.parse_tag_version('v6.2-rc1')
    assert_equal 6, v.major
    assert_equal 2, v.minor
    assert_equal 0, v.patch
    assert_equal 1, v.rc
    assert_equal 'version', v.type
  end

  def test_parse_tag_version_stable
    v = KernelVersion.parse_tag_version('v6.2')
    assert_equal 6, v.major
    assert_equal 2, v.minor
    assert_equal 0, v.patch
    assert_nil v.rc
    assert_equal 'version', v.type
  end

  def test_parse_tag_version_with_patch
    v = KernelVersion.parse_tag_version('v6.2.1')
    assert_equal 6, v.major
    assert_equal 2, v.minor
    assert_equal 1, v.patch
    assert_nil v.rc
    assert_equal 'version', v.type
  end

  # Test comparison operators

  def test_comparison_same_versions
    v1 = KernelVersion.parse_uname_version('5.10.0-14-generic')
    v2 = KernelVersion.parse_uname_version('5.10.0-14-generic')
    assert_equal v1, v2
    assert v1.eql?(v2)
    refute v1 < v2
    refute v1 > v2
    assert v1 >= v2
  end

  def test_comparison_different_ongoing
    v1 = KernelVersion.parse_uname_version('5.10.0-15-generic')
    v2 = KernelVersion.parse_uname_version('5.10.0-14-generic')
    assert v1 > v2
    assert v2 < v1
    refute_equal v1, v2
  end

  def test_comparison_different_patch
    v1 = KernelVersion.parse_uname_version('5.10.1')
    v2 = KernelVersion.parse_uname_version('5.10.0')
    assert v1 > v2
    assert v2 < v1
  end

  def test_comparison_different_minor
    v1 = KernelVersion.parse_uname_version('5.11.0')
    v2 = KernelVersion.parse_uname_version('5.10.0')
    assert v1 > v2
    assert v2 < v1
  end

  def test_comparison_different_major
    v1 = KernelVersion.parse_uname_version('6.0.0')
    v2 = KernelVersion.parse_uname_version('5.19.0')
    assert v1 > v2
    assert v2 < v1
  end

  def test_comparison_rc_vs_stable
    # RC versions should be lower than stable releases
    v_rc = KernelVersion.parse_uname_version('5.10.0-rc7-generic')
    v_stable = KernelVersion.parse_uname_version('5.10.0-generic')
    assert v_rc < v_stable
    assert v_stable > v_rc
  end

  def test_comparison_rc_versions
    v_rc1 = KernelVersion.parse_uname_version('5.10.0-rc1-generic')
    v_rc7 = KernelVersion.parse_uname_version('5.10.0-rc7-generic')
    assert v_rc1 < v_rc7
    assert v_rc7 > v_rc1
  end

  def test_comparison_ongoing_vs_rc
    # Ongoing releases should be higher than RC versions
    v_ongoing = KernelVersion.parse_uname_version('5.10.0-14-generic')
    v_rc = KernelVersion.parse_uname_version('5.10.0-rc8-generic')
    assert v_ongoing > v_rc
    assert v_rc < v_ongoing
  end

  def test_eql_heterogeneous_with_ongoing
    v1 = KernelVersion.parse_uname_version('5.10.0-14-generic')
    v2 = KernelVersion.parse_uname_version('5.10.0')
    assert v1.eql_heterogeneous?(v2)
    assert v2.eql_heterogeneous?(v1)
  end

  def test_eql_heterogeneous_different_versions
    v1 = KernelVersion.parse_uname_version('5.10.0-14-generic')
    v2 = KernelVersion.parse_uname_version('5.11.0')
    refute v1.eql_heterogeneous?(v2)
  end

  def test_eql_heterogeneous_same_ongoing
    v1 = KernelVersion.parse_uname_version('5.10.0-14-generic')
    v2 = KernelVersion.parse_uname_version('5.10.0-14-generic')
    assert v1.eql_heterogeneous?(v2)
  end

  # Test to_s method

  def test_to_s_raw
    v = KernelVersion.parse_uname_version('5.10.0-14-generic')
    assert_equal '5.10.0-14-generic', v.to_s
    assert_equal '5.10.0-14-generic', v.to_s(raw: true)
  end

  def test_to_s_formatted
    v = KernelVersion.parse_uname_version('5.10.0-14-generic')
    assert_equal '5.10.0', v.to_s(raw: false)
  end

  def test_to_s_formatted_with_rc
    v = KernelVersion.parse_uname_version('5.10.0-rc7-generic')
    assert_equal '5.10.0-rc7', v.to_s(raw: false)
  end

  # Test to_i method

  def test_to_i_basic
    v = KernelVersion.parse_uname_version('5.10.0')
    result = v.to_i
    assert result.is_a?(Integer)
    assert result > 0
  end

  def test_to_i_ordering_preserved
    v1 = KernelVersion.parse_uname_version('5.10.0')
    v2 = KernelVersion.parse_uname_version('5.11.0')
    assert v1.to_i < v2.to_i
  end

  def test_to_i_rc_lower_than_stable
    v_rc = KernelVersion.parse_uname_version('5.10.0-rc7')
    v_stable = KernelVersion.parse_uname_version('5.10.0')
    assert v_rc.to_i < v_stable.to_i
  end

  def test_to_i_with_ongoing_false
    v = KernelVersion.parse_uname_version('5.10.0-14-generic')
    result_with = v.to_i(with_ongoing: true)
    result_without = v.to_i(with_ongoing: false)
    assert result_with > result_without
  end

  # Test hash method

  def test_hash_same_versions_same_hash
    v1 = KernelVersion.parse_uname_version('5.10.0-14-generic')
    v2 = KernelVersion.parse_uname_version('5.10.0-14-generic')
    assert_equal v1.hash, v2.hash
  end

  def test_hash_different_versions_different_hash
    v1 = KernelVersion.parse_uname_version('5.10.0-14-generic')
    v2 = KernelVersion.parse_uname_version('5.10.0-15-generic')
    refute_equal v1.hash, v2.hash
  end

  # Test edge cases

  def test_large_version_numbers
    v = KernelVersion.parse_uname_version('9.99.99-999999-generic')
    assert_equal 9, v.major
    assert_equal 99, v.minor
    assert_equal 99, v.patch
    assert_equal '999999', v.ongoing
  end

  def test_double_digit_major_version
    v = KernelVersion.parse_uname_version('10.5.3-generic')
    assert_equal 10, v.major
    assert_equal 5, v.minor
    assert_equal 3, v.patch
    assert_nil v.ongoing
    assert_nil v.rc
    assert_equal 'generic', v.type
  end

  def test_raw_attribute
    version_str = '6.19-061900-sav-generic'
    v = KernelVersion.parse_uname_version(version_str)
    assert_equal version_str, v.raw
  end

  # Test sorting

  def test_sorting_multiple_versions
    versions = [
      KernelVersion.parse_uname_version('5.10.0-14-generic'),
      KernelVersion.parse_uname_version('5.11.0-rc1-generic'),
      KernelVersion.parse_uname_version('5.10.0-rc8-generic'),
      KernelVersion.parse_uname_version('6.0.0-generic'),
      KernelVersion.parse_uname_version('5.10.0-15-generic'),
    ]

    sorted = versions.sort

    # Expected order: 5.10.0-rc8 < 5.10.0-14 < 5.10.0-15 < 5.11.0-rc1 < 6.0.0
    assert_equal '5.10.0-rc8-generic', sorted[0].raw
    assert_equal '5.10.0-14-generic', sorted[1].raw
    assert_equal '5.10.0-15-generic', sorted[2].raw
    assert_equal '5.11.0-rc1-generic', sorted[3].raw
    assert_equal '6.0.0-generic', sorted[4].raw
  end
end
