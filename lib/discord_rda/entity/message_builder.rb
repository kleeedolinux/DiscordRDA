# frozen_string_literal: true

module DiscordRDA
  # Builder for creating message payloads with a DSL.
  # Supports content, embeds, components, and other message options.
  #
  class MessageBuilder
    # Initialize with base payload
    # @param base [Hash] Base payload hash
    def initialize(base = {})
      @payload = base
    end

    # Set message content
    # @param text [String] Message text
    # @return [self]
    def content(text)
      @payload[:content] = text
      self
    end

    # Add an embed to the message
    # @param title [String] Embed title
    # @param description [String] Embed description
    # @param color [Integer, Color] Embed color
    # @yield [EmbedBuilder] Block for building embed details
    # @return [self]
    def embed(title: nil, description: nil, color: nil, &block)
      @payload[:embeds] ||= []

      embed_hash = {}
      embed_hash[:title] = title if title
      embed_hash[:description] = description if description
      embed_hash[:color] = color.is_a?(Color) ? color.to_i : color if color

      if block
        builder = EmbedBuilder.new(embed_hash)
        block.call(builder)
        embed_hash = builder.to_h
      end

      @payload[:embeds] << embed_hash
      self
    end

    # Add components (buttons, select menus) to the message
    # @param type [Integer] Component type (1 for action row)
    # @yield [ComponentBuilder] Block for building components
    # @return [self]
    def components(type: 1, &block)
      @payload[:components] ||= []

      row = { type: type, components: [] }

      if block
        builder = ComponentBuilder.new(row[:components])
        block.call(builder)
      end

      @payload[:components] << row unless row[:components].empty?
      self
    end

    # Set whether this is a TTS message
    # @param enabled [Boolean] TTS enabled
    # @return [self]
    def tts(enabled = true)
      @payload[:tts] = enabled
      self
    end

    # Set allowed mentions for the message
    # @param parse [Array<String>] Parse types (roles, users, everyone)
    # @param roles [Array<String>] Specific role IDs to mention
    # @param users [Array<String>] Specific user IDs to mention
    # @param replied_user [Boolean] Whether to mention the replied user
    # @return [self]
    def allowed_mentions(parse: nil, roles: nil, users: nil, replied_user: nil)
      @payload[:allowed_mentions] = {}
      @payload[:allowed_mentions][:parse] = parse if parse
      @payload[:allowed_mentions][:roles] = roles if roles
      @payload[:allowed_mentions][:users] = users if users
      @payload[:allowed_mentions][:replied_user] = replied_user unless replied_user.nil?
      self
    end

    # Add attachments (requires multipart/form-data, not supported in basic builder)
    # @param filename [String] Attachment filename
    # @param description [String] Attachment description
    # @return [self]
    def attachment(filename:, description: nil)
      @payload[:attachments] ||= []
      @payload[:attachments] << { filename: filename, description: description }.compact
      self
    end

    # Set message flags
    # @param flags [Integer] Message flags
    # @return [self]
    def flags(flags)
      @payload[:flags] = flags
      self
    end

    # Convert builder to hash payload
    # @return [Hash] Message payload
    def to_h
      @payload
    end
  end

  # Builder for embed details
  class EmbedBuilder
    def initialize(base = {})
      @embed = base
    end

    # Set embed title
    def title(text)
      @embed[:title] = text
      self
    end

    # Set embed description
    def description(text)
      @embed[:description] = text
      self
    end

    # Set embed color
    def color(value)
      @embed[:color] = value.is_a?(Color) ? value.to_i : value
      self
    end

    # Set embed URL
    def url(link)
      @embed[:url] = link
      self
    end

    # Set embed timestamp
    def timestamp(time)
      @embed[:timestamp] = time.iso8601
      self
    end

    # Add a field to the embed
    def field(name:, value:, inline: false)
      @embed[:fields] ||= []
      @embed[:fields] << { name: name, value: value, inline: inline }
      self
    end

    # Set embed footer
    def footer(text:, icon_url: nil)
      @embed[:footer] = { text: text }
      @embed[:footer][:icon_url] = icon_url if icon_url
      self
    end

    # Set embed image
    def image(url)
      @embed[:image] = { url: url }
      self
    end

    # Set embed thumbnail
    def thumbnail(url)
      @embed[:thumbnail] = { url: url }
      self
    end

    # Set embed author
    def author(name:, url: nil, icon_url: nil)
      @embed[:author] = { name: name }
      @embed[:author][:url] = url if url
      @embed[:author][:icon_url] = icon_url if icon_url
      self
    end

    # Convert to hash
    def to_h
      @embed
    end
  end

  # Builder for message components (buttons, select menus)
  class ComponentBuilder
    def initialize(components_array)
      @components = components_array
    end

    # Add a button component
    # @param style [Integer] Button style (1=primary, 2=secondary, 3=success, 4=danger, 5=link)
    # @param label [String] Button label
    # @param custom_id [String] Custom ID for button interaction
    # @param url [String] URL for link buttons
    # @param emoji [String] Emoji for the button
    # @param disabled [Boolean] Whether button is disabled
    # @return [self]
    def button(style:, label:, custom_id: nil, url: nil, emoji: nil, disabled: false)
      btn = {
        type: 2, # Button type
        style: style,
        label: label,
        disabled: disabled
      }
      btn[:custom_id] = custom_id if custom_id
      btn[:url] = url if url
      btn[:emoji] = emoji.is_a?(Hash) ? emoji : { name: emoji } if emoji

      @components << btn
      self
    end

    # Add a select menu component
    # @param custom_id [String] Custom ID for select interaction
    # @param options [Array<Hash>] Select options
    # @param placeholder [String] Placeholder text
    # @param min_values [Integer] Minimum values to select
    # @param max_values [Integer] Maximum values to select
    # @param disabled [Boolean] Whether disabled
    # @return [self]
    def select_menu(custom_id:, options:, placeholder: nil, min_values: 1, max_values: 1, disabled: false)
      menu = {
        type: 3, # String select type
        custom_id: custom_id,
        options: options,
        min_values: min_values,
        max_values: max_values,
        disabled: disabled
      }
      menu[:placeholder] = placeholder if placeholder

      @components << menu
      self
    end
  end
end
