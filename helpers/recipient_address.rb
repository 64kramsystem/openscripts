module RecipientAddress
  CONFIG_PATH = File.expand_path('~/.fill_labels')

  private

  def configured_address_book(config_path = CONFIG_PATH)
    require 'parseconfig'
    address_book = (ParseConfig.new(config_path)['defaults'] || {})['address_book']
    raise "Set address_book in [defaults] in #{config_path}" if address_book.to_s.strip.empty?

    address_book
  end

  def cardbook_contacts(address_book)
    require 'json'
    require 'open3'
    helper = File.expand_path('../../scripts/helpers/thunderbird_apis.sh', __dir__)
    output, error, status = Open3.capture3(
      'bash', '-c', 'source "$1"; tb_cardbook_contacts "$2"', 'cardbook', helper, address_book
    )
    raise error.strip unless status.success?

    JSON.parse(output, symbolize_names: true)
  end

  def find_recipient_address(raw_recipient, address_book)
    recipient_address = raw_recipient.split("\n")
    return recipient_address if recipient_address.size > 1

    matches = recipient_matches(address_book, raw_recipient.downcase)
    raise "Recipient (pattern) not found" if matches.empty?
    return matches.first[:address] if matches.size == 1

    prompt_for_recipient(matches)
  end

  def select_recipient_address(address_book)
    matches = recipient_matches(address_book)
    raise "No recipients found" if matches.empty?

    prompt_for_recipient(matches)
  end

  def recipient_matches(address_book, pattern = nil)
    cardbook_contacts(address_book).filter_map do |card|
      name = card[:fn].to_s
      nickname = card[:nickname].to_s
      next if pattern && !name.downcase.include?(pattern) && !nickname.downcase.include?(pattern)

      { name: name, nickname: nickname, address: address_lines(card) }
    end
  end

  def prompt_for_recipient(matches)
    require 'tty-prompt'
    choices = matches.each_with_object({}) do |match, result|
      nickname = match[:nickname]
      display_name = nickname.empty? ? match[:name] : "#{match[:name]} (#{nickname})"
      result[[display_name, *match[:address].drop(1)].join(', ')] = match[:address]
    end
    TTY::Prompt.new.select("Pick recipient:", choices, filter: true)
  end

  def address_lines(card)
    addresses = card.fetch(:adrs, [])
    address = addresses.find { |candidate| home_address?(candidate) } || addresses.first
    components = (address&.fetch(:components) || []).map { |component| component.to_s.gsub(/\\[nN]/, "\n") }
    po_box, extended_address, street, locality, region, postcode, country = components.values_at(0, 1, 2, 3, 4, 5, 6).map { |component| component || '' }

    delivery_fragments = [po_box, extended_address, street].flat_map { |component| component.split("\n", -1) }.reject(&:empty?)
    delivery_lines = if delivery_fragments.size <= 2
                       delivery_fragments
                     else
                       [delivery_fragments.first, delivery_fragments.drop(1).join(', ')]
                     end

    final_line = [postcode, locality, region, country]
      .flat_map { |component| component.split("\n", -1) }
      .reject(&:empty?)
      .join(' ')
    name_line = card[:fn].to_s.gsub(/\\[nN]/, "\n").split("\n", -1).reject(&:empty?).join(' ')

    [name_line, *delivery_lines, final_line].reject(&:empty?)
  end

  def home_address?(address)
    address.fetch(:parameters).any? do |parameter|
      name, value = parameter.split('=', 2)
      name.casecmp?('TYPE') && value.to_s.split(',').any? { |type| type.casecmp?('HOME') }
    end
  end
end
