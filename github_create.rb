#!/usr/bin/env ruby

require 'json'
require 'shellwords'
require 'open3'

require 'simple_scripting/argv'

class ConfigurationHelper

  LONG_HELP = <<~'STR'
    Usage: github_create.rb pr <title> <description> [label1,label2]

    Creates a PR from the current branch.

    The labels parameter is a comma-separated list of patterns; each pattern is a case-insensitive, partial match of a label.
    If more than one label is found for a pattern, an error is raised.

    Example:

        $ github_create_pr.rb 'My Title' "This is
        a long description, but don't worry, it will be escaped.
        Just make sure to handle the quotes properly, since it's a shell string!" legacy,swf

    The above will:

    - create a PR with given title/description
    - assign the authenticated user to the PR
    - add the "Tests: Legacy" and "Needs SWF Rebuild" labels to the PR
    - open the PR (in the browser session)
  STR

  def decode_argv
    SimpleScripting::Argv.decode(
      'pr' => [
        ['-n', '--no-open-pr',                          "Don't open the PR link in the browser after creation"],
        ['-l', '--label-patterns "legacy,code review"', "Label patterns"],
        'title',
        'description',
      ],
      long_help: LONG_HELP
    )
  end

  def api_token
    ENV['GITHUB_API_TOKEN'] || raise("Missing $GITHUB_API_TOKEN")
  end

end

module OsHelpers

  def os_open(file_or_url)
    runner =
      if `uname`.strip == 'Darwin'
        'open'
      else
        'xdg-open'
      end

    exec "#{runner} #{file_or_url.shellescape}"
  end

end

class GithubApiResponseHelper

  def initialize(response_metadata)
    @response_metadata = response_metadata
  end

  def link_next_page
    link_header = find_header('Link')

    return nil if link_header.nil?

    link_header[/<(\S+)>; rel="next"/, 1]
  end

  private

  def find_header(header_name)
    @response_metadata.split("\n").detect { |header| header[/^< #{header_name}: (.*)/, 1] }
  end

end

class GithubApiHelper

  def initialize(api_token, repository_helper)
    @api_token = api_token
    @repo_helper = repository_helper
  end

  def find_labels
    response = send_github_request("https://api.github.com/repos/#{@repo_helper.owner_and_repo}/labels", multipage: true)

    response.map { |label_entry| label_entry['name'] }
  end

  # Returns a JSON object.
  #
  def send_pr_creation_request(title, description)
    head = @repo_helper.find_head

    request_data = {title: title, body: description, head: head, base: 'master'}
    request_address = "https://api.github.com/repos/#{@repo_helper.owner_and_repo}/pulls"

    response = send_github_request(request_address, data: request_data)

    if response['message'] =~ /Failed/
      message = "Error: #{response['message']}"

      if response['errors'].size.positive?
        message << ' ('
        message << response['errors'].map { |error| error['message'] }.join(', ')
        message << ')'
      end

      raise(message)
    else
      issue_number = response['number']
      issue_link = response['_links']['html']['href']

      [issue_number, issue_link]
    end
  end

  def send_assign_user_to_issue_request(issue_number)
    authenticated_user = find_authenticated_user

    request_data = {assignees: [authenticated_user]}
    request_address = "https://api.github.com/repos/#{@repo_helper.owner_and_repo}/issues/#{issue_number}/assignees"

    send_github_request(request_address, data: request_data)
  end

  def send_add_labels_to_issue_request(issue_number, labels)
    request_data = labels
    request_address = "https://api.github.com/repos/#{@repo_helper.owner_and_repo}/issues/#{issue_number}/labels"

    send_github_request(request_address, data: request_data)
  end

  private

  def find_authenticated_user
    request_address = "https://api.github.com/user"

    response = send_github_request(request_address)

    response.fetch("login")
  end

  # Send a request; resturns the JSON (Ruby) object.
  #
  # Returns the parsed response. When :multipage, the response is assumed
  # to be an array, in which case the page responses are concatenated.
  #
  # data: Hash; if present, will generate a POST request.
  #
  def send_github_request(address, data: nil, multipage: false)
    # `--data` implies `-X POST`
    #
    if data
      escaped_request_body = JSON.generate(data).shellescape
      data_option = "--data #{escaped_request_body}"
    end

    # filled only on :multipage
    parsed_responses = []

    loop do
      command = %Q{curl --verbose --silent --user "#{@repo_helper.user}:#{@api_token}" #{data_option} #{address}}
      response_metadata, response_body = nil

      Open3.popen3(command) do |stdin, stdout, stderr, wait_thread|
        response_metadata = stderr.readlines.join
        response_body = stdout.readlines.join

        if ! wait_thread.value.success?
          puts response_metadata
          puts "Error! Command: #{command}"
          exit
        end
      end

      parsed_response = JSON.parse(response_body)

      return parsed_response if ! multipage

      parsed_responses.concat(parsed_response)

      response_helper = GithubApiResponseHelper.new(response_metadata)

      address = response_helper.link_next_page

      return parsed_responses if address.nil?
    end
  end

end

class GitRepositoryHelper

  def user
    `git config --get user.email`.strip
  end

  def owner_and_repo
    # The git result is in the format `git@github.com:ticketsolve/ticketsolve.git`
    #
    raw_remote_reference = `git ls-remote --get-url origin`.strip

    raw_remote_reference[/:(.*)\.git/, 1] || raise("Unexpected remote reference format: #{raw_remote_reference.inspect}")
  end

  def find_head
    `git rev-parse --abbrev-ref HEAD`.strip
  end

end

# See https://developer.github.com/v3/pulls/#create-a-pull-request
#
class GitHubCreatePr

  include OsHelpers

  def execute(title, description, api_token, options = {})
    api_helper = GithubApiHelper.new(api_token, GitRepositoryHelper.new)

    if options[:label_patterns]
      all_labels = api_helper.find_labels
      selected_labels = select_labels(all_labels, options[:label_patterns])
    end

    issue_number, issue_link = api_helper.send_pr_creation_request(title, description)

    api_helper.send_assign_user_to_issue_request(issue_number)

    if selected_labels && ! selected_labels.empty?
      issue_edit_result = api_helper.send_add_labels_to_issue_request(issue_number, selected_labels)
      puts "Labels assigned: " + issue_edit_result.map { |entry| entry['name'].inspect }.join(', ')
    end

    if options[:no_open_pr]
      puts "PR address: #{issue_link}"
    else
      os_open(issue_link)
    end
  end

  private

  def select_labels(labels, raw_label_patterns)
    patterns = raw_label_patterns.split(',')

    patterns.map do |pattern|
      labels_found = labels.select { |label| label =~ /#{pattern}/i }

      case labels_found.size
      when 1
        labels_found.first
      when 0
        raise "No labels found for pattern: #{pattern.inspect}"
      else
        raise "Multiple labels found for pattern #{pattern.inspect}: #{labels_found}"
      end
    end
  end
end

if __FILE__ == $0
  configuration_helper = ConfigurationHelper.new

  options = configuration_helper.decode_argv[1]
  api_token = configuration_helper.api_token

  title, description = options.values_at(:title, :description)

  GitHubCreatePr.new.execute(title, description, api_token, options)
end
