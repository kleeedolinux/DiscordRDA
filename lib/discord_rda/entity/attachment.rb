# frozen_string_literal: true

module DiscordRDA
  # Represents a Discord message attachment.
  #
  class Attachment < Entity
    attribute :filename, type: :string
    attribute :description, type: :string
    attribute :content_type, type: :string
    attribute :size, type: :integer
    attribute :url, type: :string
    attribute :proxy_url, type: :string
    attribute :height, type: :integer
    attribute :width, type: :integer
    attribute :ephemeral, type: :boolean, default: false
    attribute :duration_secs, type: :float
    attribute :waveform, type: :string
    attribute :flags, type: :integer, default: 0

    # Check if attachment is an image
    # @return [Boolean] True if image
    def image?
      content_type&.start_with?('image/')
    end

    # Check if attachment is a video
    # @return [Boolean] True if video
    def video?
      content_type&.start_with?('video/')
    end

    # Check if attachment is audio
    # @return [Boolean] True if audio
    def audio?
      content_type&.start_with?('audio/')
    end

    # Check if attachment is a text file
    # @return [Boolean] True if text
    def text?
      content_type == 'text/plain' || filename.end_with?('.txt')
    end

    # Check if attachment has dimensions (image/video)
    # @return [Boolean] True if has dimensions
    def has_dimensions?
      !height.nil? && !width.nil?
    end

    # Get dimensions as [width, height]
    # @return [Array<Integer>, nil] Dimensions
    def dimensions
      [width, height] if has_dimensions?
    end

    # Check if attachment is ephemeral (will be deleted)
    # @return [Boolean] True if ephemeral
    def ephemeral?
      ephemeral
    end

    # Get file size in human readable format
    # @return [String] Human readable size
    def size_human
      bytes = size.to_i
      return "#{bytes}B" if bytes < 1024
      return "#{(bytes / 1024.0).round(1)}KB" if bytes < 1024 * 1024
      return "#{(bytes / (1024.0 * 1024)).round(1)}MB" if bytes < 1024 * 1024 * 1024
      "#{(bytes / (1024.0 * 1024 * 1024)).round(1)}GB"
    end

    # Get duration formatted (for voice messages)
    # @return [String, nil] Formatted duration
    def duration_formatted
      return nil unless duration_secs

      minutes = (duration_secs / 60).floor
      seconds = (duration_secs % 60).floor
      "#{minutes}:#{seconds.to_s.rjust(2, '0')}"
    end

    # Check if this is a voice message
    # @return [Boolean] True if voice message
    def voice_message?
      !waveform.nil? || filename == 'voice-message.ogg'
    end
  end
end
