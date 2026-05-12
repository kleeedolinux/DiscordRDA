# frozen_string_literal: true

module DiscordRDA
  # Interaction represents a Discord interaction (slash command, button click, etc.)
  # Provides full response handling including messages, modals, and autocomplete.
  #
  class Interaction < Entity
    # Interaction types
    TYPES = {
      ping: 1,
      application_command: 2,
      message_component: 3,
      application_command_autocomplete: 4,
      modal_submit: 5,
      premium_required: 6
    }.freeze

    # Interaction callback types (response types)
    CALLBACK_TYPES = {
      pong: 1,                                    # ACK a Ping
      channel_message_with_source: 4,             # Respond with message
      deferred_channel_message_with_source: 5,      # ACK, edit later
      deferred_update_message: 6,                 # For components, ACK and edit later
      update_message: 7,                           # For components, edit message
      application_command_autocomplete_result: 8,  # Autocomplete choices
      modal: 9,                                    # Respond with modal
      premium_required: 10                         # Require premium
    }.freeze

    # Interaction context types
    CONTEXT_TYPES = {
      guild: 0,
      bot_dm: 1,
      private_channel: 2
    }.freeze

    attribute :application_id, type: :snowflake
    attribute :type, type: :integer
    attribute :data, type: :hash
    attribute :guild_id, type: :snowflake
    attribute :channel_id, type: :snowflake
    attribute :channel, type: :hash
    attribute :member, type: :hash
    attribute :user, type: :hash
    attribute :token, type: :string
    attribute :version, type: :integer
    attribute :message, type: :hash
    attribute :locale, type: :string
    attribute :guild_locale, type: :string
    attribute :entitlements, type: :array
    attribute :authorizing_integration_owners, type: :hash
    attribute :context, type: :integer

    # Class-level API client
    class << self
      attr_accessor :api
      attr_accessor :supervisor
    end

    # Get interaction type as symbol
    # @return [Symbol] Interaction type
    def interaction_type
      TYPES.key(type) || :unknown
    end

    # Check if this is a ping interaction
    # @return [Boolean] True if ping
    def ping?
      type == 1
    end

    # Check if this is an application command (slash command)
    # @return [Boolean] True if slash command
    def command?
      type == 2
    end

    # Check if this is a message component interaction (button/select)
    # @return [Boolean] True if component
    def component?
      type == 3
    end

    # Check if this is an autocomplete interaction
    # @return [Boolean] True if autocomplete
    def autocomplete?
      type == 4
    end

    # Check if this is a modal submit
    # @return [Boolean] True if modal submit
    def modal_submit?
      type == 5
    end

    # Get context type as symbol
    # @return [Symbol] Context type
    def context_type
      CONTEXT_TYPES.key(@raw_data['context']) || :guild
    end

    # Check if interaction is from a guild
    # @return [Boolean] True if guild context
    def guild_context?
      context_type == :guild
    end

    # Check if interaction is from a DM
    # @return [Boolean] True if DM context
    def dm_context?
      context_type == :bot_dm || context_type == :private_channel
    end

    # Get the user who triggered the interaction
    # @return [User] User entity
    def user
      if member && member['user']
        User.new(member['user'].merge('member' => member))
      elsif @raw_data['user']
        User.new(@raw_data['user'])
      else
        nil
      end
    end

    # Get the guild member who triggered the interaction
    # @return [Member, nil] Member entity (nil if not in guild)
    def member
      return nil unless @raw_data['member']
      Member.new(@raw_data['member'].merge('guild_id' => guild_id.to_s))
    end

    # Get the command data for application command interactions
    # @return [Hash, nil] Command data
    def command_data
      return nil unless command?
      @raw_data['data']
    end

    # Get the command name
    # @return [String, nil] Command name
    def command_name
      command_data&.dig('name')
    end

    # Get command options as a hash
    # @return [Hash] Option name to value mapping
    def options
      return {} unless command_data && command_data['options']

      opts = {}
      command_data['options'].each do |opt|
        opts[opt['name']] = resolve_option_value(opt)
      end
      opts
    end

    # Get a specific option value
    # @param name [String] Option name
    # @return [Object, nil] Option value
    def option(name)
      options[name.to_s]
    end

    # Get focused option for autocomplete
    # @return [Hash, nil] Focused option data
    def focused_option
      return nil unless autocomplete?
      command_data&.dig('options')&.find { |opt| opt['focused'] }
    end

    # Get component data for message component interactions
    # @return [Hash, nil] Component data
    def component_data
      return nil unless component?
      @raw_data['data']
    end

    # Get custom ID from component
    # @return [String, nil] Custom ID
    def custom_id
      component_data&.dig('custom_id')
    end

    # Get component type
    # @return [Integer, nil] Component type
    def component_type
      component_data&.dig('component_type')
    end

    # Get selected values from select menu
    # @return [Array<String>] Selected values
    def selected_values
      component_data&.dig('values') || []
    end

    # Get modal submit data
    # @return [Hash, nil] Modal data with components
    def modal_data
      return nil unless modal_submit?
      @raw_data['data']
    end

    # Get values from modal submission
    # @return [Hash] Component custom_id to value mapping
    def modal_values
      return {} unless modal_submit?

      values = {}
      modal_data&.dig('components')&.each do |row|
        row['components']&.each do |component|
          if component['custom_id'] && component['value']
            values[component['custom_id']] = component['value']
          end
        end
      end
      values
    end

    # Get a modal value by custom_id
    # @param id [String] Component custom_id
    # @return [String, nil] Component value
    def modal_value(id)
      modal_values[id.to_s]
    end

    # Get the original message that triggered this component interaction
    # @return [Message, nil] Original message
    def original_message
      return nil unless @raw_data['message']
      Message.new(@raw_data['message'])
    end

    # Respond to the interaction with a message
    # @param content [String] Message content
    # @param options [Hash] Response options (embeds, components, etc.)
    # @yield [MessageBuilder] Optional builder block
    # @return [void]
    def respond(content = nil, **options, &block)
      raise 'API client not configured' unless self.class.api

      payload = { content: content }.merge(options).compact

      if block
        builder = MessageBuilder.new(payload)
        block.call(builder)
        payload = builder.to_h
      end

      body = {
        type: CALLBACK_TYPES[:channel_message_with_source],
        data: payload
      }

      self.class.api.post("/interactions/#{id}/#{token}/callback", body: body)
    end

    # Defer the response (show "thinking..." state)
    # @param ephemeral [Boolean] Whether the eventual response should be ephemeral
    # @return [void]
    def defer(ephemeral: false)
      raise 'API client not configured' unless self.class.api

      data = ephemeral ? { flags: 64 } : {}
      body = {
        type: CALLBACK_TYPES[:deferred_channel_message_with_source],
        data: data
      }

      self.class.api.post("/interactions/#{id}/#{token}/callback", body: body)
    end

    # Defer updating the original message (for components)
    # @return [void]
    def defer_update
      raise 'API client not configured' unless self.class.api
      raise 'Only available for component interactions' unless component?

      body = {
        type: CALLBACK_TYPES[:deferred_update_message]
      }

      self.class.api.post("/interactions/#{id}/#{token}/callback", body: body)
    end

    # Update the original message (for components)
    # @param content [String] New content
    # @param options [Hash] Update options
    # @yield [MessageBuilder] Optional builder block
    # @return [void]
    def update_message(content = nil, **options, &block)
      raise 'API client not configured' unless self.class.api
      raise 'Only available for component interactions' unless component?

      payload = { content: content }.merge(options).compact

      if block
        builder = MessageBuilder.new(payload)
        block.call(builder)
        payload = builder.to_h
      end

      body = {
        type: CALLBACK_TYPES[:update_message],
        data: payload
      }

      self.class.api.post("/interactions/#{id}/#{token}/callback", body: body)
    end

    # Respond with autocomplete choices
    # @param choices [Array<Hash>] Choice objects with name and value
    # @return [void]
    def autocomplete(choices)
      raise 'API client not configured' unless self.class.api
      raise 'Only available for autocomplete interactions' unless autocomplete?

      body = {
        type: CALLBACK_TYPES[:application_command_autocomplete_result],
        data: { choices: choices }
      }

      self.class.api.post("/interactions/#{id}/#{token}/callback", body: body)
    end

    # Respond with a modal
    # @param custom_id [String] Modal custom ID
    # @param title [String] Modal title
    # @param components [Array<Hash>] Modal components (text inputs)
    # @yield [ModalBuilder] Optional builder block
    # @return [void]
    def modal(custom_id:, title:, components: nil, &block)
      raise 'API client not configured' unless self.class.api

      data = {
        custom_id: custom_id,
        title: title,
        components: components || []
      }

      if block
        builder = ModalBuilder.new(data)
        block.call(builder)
        data = builder.to_h
      end

      body = {
        type: CALLBACK_TYPES[:modal],
        data: data
      }

      self.class.api.post("/interactions/#{id}/#{token}/callback", body: body)
    end

    # Edit the original interaction response
    # @param content [String] New content
    # @param options [Hash] Edit options
    # @yield [MessageBuilder] Optional builder block
    # @return [Message] Updated message
    def edit_original(content = nil, **options, &block)
      raise 'API client not configured' unless self.class.api

      payload = { content: content }.merge(options).compact

      if block
        builder = MessageBuilder.new(payload)
        block.call(builder)
        payload = builder.to_h
      end

      data = self.class.api.patch("/webhooks/#{application_id}/#{token}/messages/@original", body: payload)
      Message.new(data)
    end

    # Delete the original interaction response
    # @return [void]
    def delete_original
      raise 'API client not configured' unless self.class.api

      self.class.api.delete("/webhooks/#{application_id}/#{token}/messages/@original")
    end

    # Create a followup message
    # @param content [String] Message content
    # @param options [Hash] Message options
    # @yield [MessageBuilder] Optional builder block
    # @return [Message] Created message
    def followup(content = nil, **options, &block)
      raise 'API client not configured' unless self.class.api

      payload = { content: content }.merge(options).compact

      if block
        builder = MessageBuilder.new(payload)
        block.call(builder)
        payload = builder.to_h
      end

      data = self.class.api.post("/webhooks/#{application_id}/#{token}", body: payload)
      Message.new(data)
    end

    # Get a followup message
    # @param message_id [String] Followup message ID
    # @return [Message] Followup message
    def get_followup(message_id)
      raise 'API client not configured' unless self.class.api

      data = self.class.api.get("/webhooks/#{application_id}/#{token}/messages/#{message_id}")
      Message.new(data)
    end

    # Edit a followup message
    # @param message_id [String] Followup message ID
    # @param content [String] New content
    # @param options [Hash] Edit options
    # @yield [MessageBuilder] Optional builder block
    # @return [Message] Updated message
    def edit_followup(message_id, content = nil, **options, &block)
      raise 'API client not configured' unless self.class.api

      payload = { content: content }.merge(options).compact

      if block
        builder = MessageBuilder.new(payload)
        block.call(builder)
        payload = builder.to_h
      end

      data = self.class.api.patch("/webhooks/#{application_id}/#{token}/messages/#{message_id}", body: payload)
      Message.new(data)
    end

    # Delete a followup message
    # @param message_id [String] Followup message ID
    # @return [void]
    def delete_followup(message_id)
      raise 'API client not configured' unless self.class.api

      self.class.api.delete("/webhooks/#{application_id}/#{token}/messages/#{message_id}")
    end

    def run_isolated(ruby_code:, timeout_seconds: 15, memory_limit_mb: nil, env: {})
      raise 'Execution supervisor not configured' unless self.class.supervisor

      self.class.supervisor.run_isolated(
        ruby_code: ruby_code,
        timeout_seconds: timeout_seconds,
        memory_limit_mb: memory_limit_mb,
        env: env
      )
    end

    # Show premium required response
    # @return [void]
    def premium_required
      raise 'API client not configured' unless self.class.api

      body = {
        type: CALLBACK_TYPES[:premium_required]
      }

      self.class.api.post("/interactions/#{id}/#{token}/callback", body: body)
    end

    private

    def resolve_option_value(opt)
      value = opt['value']

      # Resolve based on option type
      case opt['type']
      when 6 # user
        resolve_user(value)
      when 7 # channel
        resolve_channel(value)
      when 8 # role
        resolve_role(value)
      when 11 # attachment
        resolve_attachment(value)
      else
        value
      end
    end

    def resolve_user(user_id)
      # Try to get from resolved data
      resolved = command_data&.dig('resolved', 'users', user_id.to_s)
      resolved ? User.new(resolved) : user_id
    end

    def resolve_channel(channel_id)
      resolved = command_data&.dig('resolved', 'channels', channel_id.to_s)
      resolved ? Channel.new(resolved) : channel_id
    end

    def resolve_role(role_id)
      resolved = command_data&.dig('resolved', 'roles', role_id.to_s)
      resolved ? Role.new(resolved) : role_id
    end

    def resolve_attachment(attachment_id)
      resolved = command_data&.dig('resolved', 'attachments', attachment_id.to_s)
      resolved ? Attachment.new(resolved) : attachment_id
    end
  end

  # Builder for creating modals
  class ModalBuilder
    def initialize(data = {})
      @data = data
      @components = []
    end

    # Add a short text input
    # @param custom_id [String] Input custom ID
    # @param label [String] Input label
    # @param placeholder [String] Placeholder text
    # @param min_length [Integer] Minimum length
    # @param max_length [Integer] Maximum length
    # @param required [Boolean] Whether required
    # @param value [String] Default value
    def short(custom_id:, label:, placeholder: nil, min_length: nil, max_length: nil, required: true, value: nil)
      add_text_input(1, custom_id, label, placeholder: placeholder, min_length: min_length, max_length: max_length, required: required, value: value)
    end

    # Add a paragraph text input
    # @param custom_id [String] Input custom ID
    # @param label [String] Input label
    # @param placeholder [String] Placeholder text
    # @param min_length [Integer] Minimum length
    # @param max_length [Integer] Maximum length
    # @param required [Boolean] Whether required
    # @param value [String] Default value
    def paragraph(custom_id:, label:, placeholder: nil, min_length: nil, max_length: nil, required: true, value: nil)
      add_text_input(2, custom_id, label, placeholder: placeholder, min_length: min_length, max_length: max_length, required: required, value: value)
    end

    # Convert to hash for API
    # @return [Hash] Modal data
    def to_h
      @data[:components] = @components.map { |c| { type: 1, components: [c] } }
      @data
    end

    private

    def add_text_input(style, custom_id, label, placeholder: nil, min_length: nil, max_length: nil, required: true, value: nil)
      component = {
        type: 4, # Text Input
        style: style,
        custom_id: custom_id,
        label: label,
        required: required
      }
      component[:placeholder] = placeholder if placeholder
      component[:min_length] = min_length if min_length
      component[:max_length] = max_length if max_length
      component[:value] = value if value

      @components << component
      self
    end
  end
end
