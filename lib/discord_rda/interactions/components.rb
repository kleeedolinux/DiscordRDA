# frozen_string_literal: true

module DiscordRDA
  # Component V2 - Discord's updated message components system.
  # Supports Action Rows, Buttons, Select Menus, and Text Inputs.
  #
  module Components
    # Component types
    TYPES = {
      action_row: 1,
      button: 2,
      string_select: 3,
      text_input: 4,
      user_select: 5,
      role_select: 6,
      mentionable_select: 7,
      channel_select: 8,
      section: 9,
      text_display: 10,
      thumbnail: 11,
      media_gallery: 12,
      file: 13,
      separator: 14,
      container: 17
    }.freeze

    # Button styles
    BUTTON_STYLES = {
      primary: 1,     # Blurple
      secondary: 2,   # Grey
      success: 3,     # Green
      danger: 4,      # Red
      link: 5,        # URL button
      premium: 6      # SKU button
    }.freeze

    # Text input styles
    TEXT_INPUT_STYLES = {
      short: 1,       # Single line
      paragraph: 2    # Multi-line
    }.freeze

    # Base component class
    class Base
      attr_reader :type, :data

      def initialize(type, data = {})
        @type = type
        @data = { type: TYPES[type] || type }.merge(data)
      end

      # Convert to hash for API
      # @return [Hash] Component hash
      def to_h
        @data
      end
    end

    # Action Row - Container for other components (max 5 components)
    class ActionRow < Base
      def initialize
        super(:action_row)
        @components = []
      end

      # Add a component to this row
      # @param component [Base] Component to add
      # @return [self]
      def add(component)
        raise ArgumentError, 'ActionRow can only contain non-row components' if component.is_a?(ActionRow)
        raise ArgumentError, 'ActionRow can contain max 5 components' if @components.length >= 5
        @components << component
        @data[:components] = @components.map(&:to_h)
        self
      end

      # Button helper
      # @param kwargs [Hash] Button options
      # @return [self]
      def button(**kwargs)
        add(Button.new(**kwargs))
      end

      # String select helper
      # @param kwargs [Hash] Select options
      # @return [self]
      def string_select(**kwargs)
        add(StringSelect.new(**kwargs))
      end

      # User select helper
      # @param kwargs [Hash] Select options
      # @return [self]
      def user_select(**kwargs)
        add(UserSelect.new(**kwargs))
      end

      # Role select helper
      # @param kwargs [Hash] Select options
      # @return [self]
      def role_select(**kwargs)
        add(RoleSelect.new(**kwargs))
      end

      # Mentionable select helper
      # @param kwargs [Hash] Select options
      # @return [self]
      def mentionable_select(**kwargs)
        add(MentionableSelect.new(**kwargs))
      end

      # Channel select helper
      # @param kwargs [Hash] Select options
      # @return [self]
      def channel_select(**kwargs)
        add(ChannelSelect.new(**kwargs))
      end
    end

    # Button component
    class Button < Base
      # @param style [Symbol, Integer] Button style (:primary, :secondary, :success, :danger, :link)
      # @param label [String] Button text
      # @param custom_id [String] Custom ID for interaction (not for link buttons)
      # @param url [String] URL for link buttons
      # @param emoji [Hash, String] Emoji hash or unicode string
      # @param sku_id [String] SKU ID for premium buttons
      # @param disabled [Boolean] Whether disabled
      def initialize(style:, label: nil, custom_id: nil, url: nil, emoji: nil, sku_id: nil, disabled: false)
        style_val = BUTTON_STYLES[style] || style
        data = { style: style_val, disabled: disabled }

        data[:label] = label if label
        data[:custom_id] = custom_id if custom_id
        data[:url] = url if url && style_val == 5
        data[:emoji] = emoji.is_a?(String) ? { name: emoji } : emoji if emoji
        data[:sku_id] = sku_id if sku_id && style_val == 6

        super(:button, data)
      end

      # Create a primary (blurple) button
      # @param label [String] Button text
      # @param custom_id [String] Custom ID
      def self.primary(label:, custom_id:, **options)
        new(style: :primary, label: label, custom_id: custom_id, **options)
      end

      # Create a secondary (grey) button
      # @param label [String] Button text
      # @param custom_id [String] Custom ID
      def self.secondary(label:, custom_id:, **options)
        new(style: :secondary, label: label, custom_id: custom_id, **options)
      end

      # Create a success (green) button
      # @param label [String] Button text
      # @param custom_id [String] Custom ID
      def self.success(label:, custom_id:, **options)
        new(style: :success, label: label, custom_id: custom_id, **options)
      end

      # Create a danger (red) button
      # @param label [String] Button text
      # @param custom_id [String] Custom ID
      def self.danger(label:, custom_id:, **options)
        new(style: :danger, label: label, custom_id: custom_id, **options)
      end

      # Create a link button
      # @param label [String] Button text
      # @param url [String] URL to open
      def self.link(label:, url:, **options)
        new(style: :link, label: label, url: url, **options)
      end
    end

    # Base select menu class
    class SelectMenu < Base
      # @param type [Symbol, Integer] Select type
      # @param custom_id [String] Custom ID
      # @param placeholder [String] Placeholder text
      # @param min_values [Integer] Minimum values to select
      # @param max_values [Integer] Maximum values to select
      # @param disabled [Boolean] Whether disabled
      def initialize(type:, custom_id:, placeholder: nil, min_values: 1, max_values: 1, disabled: false)
        data = {
          custom_id: custom_id,
          min_values: min_values,
          max_values: max_values,
          disabled: disabled
        }
        data[:placeholder] = placeholder if placeholder
        super(type, data)
      end
    end

    # String select menu (dropdown with text options)
    class StringSelect < SelectMenu
      # @param custom_id [String] Custom ID
      # @param options [Array<Hash>] Select options with label, value, description, emoji
      # @param placeholder [String] Placeholder text
      # @param min_values [Integer] Minimum values to select
      # @param max_values [Integer] Maximum values to select
      # @param disabled [Boolean] Whether disabled
      def initialize(custom_id:, options:, placeholder: nil, min_values: 1, max_values: 1, disabled: false)
        super(type: :string_select, custom_id: custom_id, placeholder: placeholder, min_values: min_values, max_values: max_values, disabled: disabled)
        @data[:options] = options.map { |opt| normalize_option(opt) }
      end

      private

      def normalize_option(opt)
        option = {
          label: opt[:label],
          value: opt[:value],
          default: opt[:default] || false
        }
        option[:description] = opt[:description] if opt[:description]
        option[:emoji] = opt[:emoji].is_a?(String) ? { name: opt[:emoji] } : opt[:emoji] if opt[:emoji]
        option
      end
    end

    # User select menu (dropdown showing users)
    class UserSelect < SelectMenu
      def initialize(custom_id:, placeholder: nil, min_values: 1, max_values: 1, disabled: false)
        super(type: :user_select, custom_id: custom_id, placeholder: placeholder, min_values: min_values, max_values: max_values, disabled: disabled)
      end
    end

    # Role select menu (dropdown showing roles)
    class RoleSelect < SelectMenu
      def initialize(custom_id:, placeholder: nil, min_values: 1, max_values: 1, disabled: false)
        super(type: :role_select, custom_id: custom_id, placeholder: placeholder, min_values: min_values, max_values: max_values, disabled: disabled)
      end
    end

    # Mentionable select menu (dropdown showing users and roles)
    class MentionableSelect < SelectMenu
      def initialize(custom_id:, placeholder: nil, min_values: 1, max_values: 1, disabled: false)
        super(type: :mentionable_select, custom_id: custom_id, placeholder: placeholder, min_values: min_values, max_values: max_values, disabled: disabled)
      end
    end

    # Channel select menu (dropdown showing channels)
    class ChannelSelect < SelectMenu
      # @param custom_id [String] Custom ID
      # @param channel_types [Array<Integer>] Channel types to show
      # @param placeholder [String] Placeholder text
      # @param min_values [Integer] Minimum values to select
      # @param max_values [Integer] Maximum values to select
      # @param disabled [Boolean] Whether disabled
      def initialize(custom_id:, channel_types: nil, placeholder: nil, min_values: 1, max_values: 1, disabled: false)
        super(type: :channel_select, custom_id: custom_id, placeholder: placeholder, min_values: min_values, max_values: max_values, disabled: disabled)
        @data[:channel_types] = channel_types if channel_types
      end
    end

    # Text Input (for modals)
    class TextInput < Base
      # @param style [Symbol, Integer] Input style (:short or :paragraph)
      # @param custom_id [String] Custom ID
      # @param label [String] Input label
      # @param placeholder [String] Placeholder text
      # @param min_length [Integer] Minimum length
      # @param max_length [Integer] Maximum length
      # @param required [Boolean] Whether required
      # @param value [String] Default value
      def initialize(style:, custom_id:, label:, placeholder: nil, min_length: nil, max_length: nil, required: true, value: nil)
        style_val = TEXT_INPUT_STYLES[style] || style
        data = {
          style: style_val,
          custom_id: custom_id,
          label: label,
          required: required
        }
        data[:placeholder] = placeholder if placeholder
        data[:min_length] = min_length if min_length
        data[:max_length] = max_length if max_length
        data[:value] = value if value

        super(:text_input, data)
      end

      # Create a short text input
      # @param kwargs [Hash] Text input options
      def self.short(**kwargs)
        new(style: :short, **kwargs)
      end

      # Create a paragraph text input
      # @param kwargs [Hash] Text input options
      def self.paragraph(**kwargs)
        new(style: :paragraph, **kwargs)
      end
    end

    # Section component (V2)
    class Section < Base
      def initialize(components:, accessory: nil, id: nil)
        data = { components: components.map(&:to_h) }
        data[:accessory] = accessory.to_h if accessory
        data[:id] = id if id
        super(:section, data)
      end
    end

    # Text Display component (V2)
    class TextDisplay < Base
      def initialize(content:, id: nil)
        data = { content: content }
        data[:id] = id if id
        super(:text_display, data)
      end
    end

    # Thumbnail component (V2)
    class Thumbnail < Base
      def initialize(media:, description: nil, spoiler: false, id: nil)
        data = { media: media }
        data[:description] = description if description
        data[:spoiler] = spoiler if spoiler
        data[:id] = id if id
        super(:thumbnail, data)
      end
    end

    # Media Gallery component (V2)
    class MediaGallery < Base
      def initialize(items:, id: nil)
        data = { items: items.map(&:to_h) }
        data[:id] = id if id
        super(:media_gallery, data)
      end
    end

    # File component (V2)
    class FileComponent < Base
      def initialize(file:, spoiler: false, id: nil)
        data = { file: file }
        data[:spoiler] = spoiler if spoiler
        data[:id] = id if id
        super(:file, data)
      end
    end

    # Separator component (V2)
    class Separator < Base
      def initialize(divider: true, spacing: nil, id: nil)
        data = { divider: divider }
        data[:spacing] = spacing if spacing
        data[:id] = id if id
        super(:separator, data)
      end
    end

    # Container component (V2)
    class Container < Base
      def initialize(components:, accent_color: nil, spoiler: false, id: nil)
        data = { components: components.map(&:to_h) }
        data[:accent_color] = accent_color if accent_color
        data[:spoiler] = spoiler if spoiler
        data[:id] = id if id
        super(:container, data)
      end
    end

    # Builder class for constructing component rows
    class Builder
      def initialize
        @rows = []
        @current_row = nil
      end

      # Start a new action row
      # @yield [ActionRow] Row builder
      # @return [self]
      def row
        @current_row = ActionRow.new
        yield @current_row if block_given?
        @rows << @current_row
        @current_row = nil
        self
      end

      # Add a button to current row
      # @param kwargs [Hash] Button options
      # @return [self]
      def button(**kwargs)
        ensure_row
        @current_row.add(Button.new(**kwargs))
        self
      end

      # Add a string select to current row
      # @param kwargs [Hash] Select options
      # @return [self]
      def string_select(**kwargs)
        ensure_row
        @current_row.add(StringSelect.new(**kwargs))
        self
      end

      # Add a user select to current row
      # @param kwargs [Hash] Select options
      # @return [self]
      def user_select(**kwargs)
        ensure_row
        @current_row.add(UserSelect.new(**kwargs))
        self
      end

      # Add a role select to current row
      # @param kwargs [Hash] Select options
      # @return [self]
      def role_select(**kwargs)
        ensure_row
        @current_row.add(RoleSelect.new(**kwargs))
        self
      end

      # Add a mentionable select to current row
      # @param kwargs [Hash] Select options
      # @return [self]
      def mentionable_select(**kwargs)
        ensure_row
        @current_row.add(MentionableSelect.new(**kwargs))
        self
      end

      # Add a channel select to current row
      # @param kwargs [Hash] Select options
      # @return [self]
      def channel_select(**kwargs)
        ensure_row
        @current_row.add(ChannelSelect.new(**kwargs))
        self
      end

      # Convert to array of component hashes
      # @return [Array<Hash>] Components array
      def to_a
        @rows.map(&:to_h)
      end

      private

      def ensure_row
        @current_row ||= ActionRow.new
        @rows << @current_row unless @rows.include?(@current_row)
      end
    end

    # Convenience method to create components
    # @yield [Builder] Component builder
    # @return [Array<Hash>] Components array
    def self.build(&block)
      builder = Builder.new
      block.call(builder) if block
      builder.to_a
    end
  end
end
