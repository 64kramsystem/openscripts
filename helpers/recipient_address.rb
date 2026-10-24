module RecipientAddress
  CONFIG_PATH = File.expand_path('~/.fill_labels')

  private

  def configured_address_book(config_path = CONFIG_PATH)
    require 'parseconfig'
    address_book = (ParseConfig.new(config_path)['defaults'] || {})['address_book']
    raise "Set address_book in [defaults] in #{config_path}" if address_book.to_s.strip.empty?

    File.expand_path(address_book)
  end

  def find_recipient_address(raw_recipient, vcard_path)
    recipient_address = raw_recipient.split("\n")
    return recipient_address if recipient_address.size > 1

    pattern = raw_recipient.downcase

    matches = recipient_matches(vcard_path, pattern)

    raise "Recipient (pattern) not found" if matches.empty?
    return matches.first[:address] if matches.size == 1

    prompt_for_recipient(matches)
  end

  def select_recipient_address(vcard_path)
    matches = recipient_matches(vcard_path)
    raise "No recipients found" if matches.empty?

    prompt_for_recipient(matches)
  end

  def recipient_matches(vcard_path, pattern = nil)
    parse_vcards(vcard_path).filter_map do |card|
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

  def parse_vcards(path)
    unfolded_lines = File.readlines(path, chomp: true).each_with_object([]) do |line, lines|
      line.start_with?(' ', "\t") ? lines[-1] << line[1..] : lines << line
    end

    cards = []
    card = nil
    unfolded_lines.each do |line|
      case line
      when 'BEGIN:VCARD' then card = { adrs: [] }
      when 'END:VCARD'   then cards << card if card
      else
        next unless card && line.include?(':')

        field, value = line.split(':', 2)
        property, *parameters = field.split(';')
        case property.upcase
        when 'FN'       then card[:fn] = unescape_vcard_text(value)
        when 'NICKNAME' then card[:nickname] = unescape_vcard_text(value)
        when 'ADR'      then card[:adrs] << { parameters: parameters, value: value }
        end
      end
    end
    cards
  end

  def address_lines(card)
    addresses = card.fetch(:adrs, [])
    address = addresses.find { |candidate| home_address?(candidate) } || addresses.first
    components = split_adr_components(address&.fetch(:value, '').to_s).map { |component| unescape_vcard_text(component) }
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
    name_line = card[:fn].to_s.split("\n", -1).reject(&:empty?).join(' ')

    [name_line, *delivery_lines, final_line].reject(&:empty?)
  end

  def split_adr_components(value)
    components = [String.new]
    backslash_count = 0

    value.each_char do |character|
      character == ';' && backslash_count.even? ? components << String.new : components.last << character
      backslash_count = character == '\\' ? backslash_count + 1 : 0
    end

    components
  end

  def unescape_vcard_text(value)
    value.gsub(/\\([\\,;nN])/) do
      escaped_character = Regexp.last_match(1)
      escaped_character.match?(/[nN]/) ? "\n" : escaped_character
    end
  end

  def home_address?(address)
    address.fetch(:parameters).any? do |parameter|
      name, value = parameter.split('=', 2)
      name.casecmp?('TYPE') && value.to_s.split(',').any? { |type| type.casecmp?('HOME') }
    end
  end

end
