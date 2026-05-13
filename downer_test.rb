#!/usr/bin/env ruby

require 'minitest/autorun'

# `load` (vs `require`) accepts an extensionless filename; the `__FILE__ == $0`
# guard at the bottom of `downer` prevents the CLI entry point from running.
load File.expand_path('downer', __dir__)

class DownerTest < Minitest::Test
  def setup
    @downer = Downer.new
  end

  # --- find_file_link -------------------------------------------------------

  def test_find_file_link_returns_first_match_when_absolute
    stub_page('junk https://example.com/foo-1.2.3.deb more junk')

    result = @downer.send(
      :find_file_link,
      'http://host/page',
      %r{https://example\.com/foo-[\d.]+\.deb},
      relative_path: false
    )
    assert_equal 'https://example.com/foo-1.2.3.deb', result
  end

  # GitHub releases page lists newest first; downer relies on `String#[regex]`
  # returning the leftmost match.
  def test_find_file_link_returns_first_occurrence_among_multiple_matches
    stub_page(
      'newer /owner/repo/releases/download/1.2.0/file-1.2.0.deb ' \
      'older /owner/repo/releases/download/1.0.0/file-1.0.0.deb'
    )

    result = @downer.send(
      :find_file_link,
      'https://github.com/owner/repo/releases',
      %r{/owner/repo/releases/download/[\d.]+/file-[\d.]+\.deb},
      relative_path: true
    )
    assert_equal 'https://github.com/owner/repo/releases/download/1.2.0/file-1.2.0.deb', result
  end

  def test_find_file_link_prepends_scheme_and_host_when_relative_path
    stub_page('x /owner/repo/releases/download/1.0/file.deb x')

    result = @downer.send(
      :find_file_link,
      'https://github.com/owner/repo/releases',
      %r{/owner/repo/releases/download/[\d.]+/file\.deb},
      relative_path: true
    )
    assert_equal 'https://github.com/owner/repo/releases/download/1.0/file.deb', result
  end

  def test_find_file_link_raises_when_no_match
    stub_page('no matches here')

    err = nil
    capture_io do
      err = assert_raises(RuntimeError) do
        @downer.send(:find_file_link, 'http://host', /nothing-matches/, relative_path: false)
      end
    end
    assert_match(/File link not Found/, err.message)
  end

  # --- install dispatch -----------------------------------------------------

  def test_install_with_application_runs_app_against_file
    cmd = nil
    capture_io { cmd = capture_install_command { @downer.send(:install, '/tmp/installer.run', application: 'sh') } }
    assert_equal 'sh /tmp/installer.run', cmd
  end

  def test_install_deb_invokes_gdebi_noninteractive
    cmd = nil
    capture_io { cmd = capture_install_command { @downer.send(:install, '/tmp/rustdesk-1.4.6-x86_64.deb') } }
    assert_equal 'sudo gdebi --non-interactive /tmp/rustdesk-1.4.6-x86_64.deb', cmd
  end

  def test_install_raises_for_unsupported_extension
    stub_system_success
    err = assert_raises(RuntimeError) do
      @downer.send(:install, '/tmp/something.xyz')
    end
    assert_match(/Package extension not supported: xyz/, err.message)
  end

  private

  def stub_page(body)
    @downer.define_singleton_method(:download_page) { |*_args| body }
  end

  # Records the command passed to `system` and sets `$?` to success so the
  # post-check in `install` doesn't trip.
  def capture_install_command
    captured = nil
    @downer.define_singleton_method(:system) do |*args, **_kwargs|
      captured = args.first
      Kernel.system('true')
      true
    end
    yield
    captured
  end

  def stub_system_success
    @downer.define_singleton_method(:system) do |*_args, **_kwargs|
      Kernel.system('true')
      true
    end
  end
end
