# frozen_string_literal: true

module DiscordRDA
  # Represents a Discord message embed.
  #
  class Embed < Entity
    # Embed types
    TYPES = %w[rich image video gifv article link].freeze

    attribute :title, type: :string
    attribute :type, type: :string, default: 'rich'
    attribute :description, type: :string
    attribute :url, type: :string
    attribute :timestamp, type: :time
    attribute :color, type: :integer, default: 0
    attribute :footer, type: :hash
    attribute :image, type: :hash
    attribute :thumbnail, type: :hash
    attribute :video, type: :hash
    attribute :provider, type: :hash
    attribute :author, type: :hash
    attribute :fields, type: :array, default: []

    # Get color as Color object
    # @return [Color] Embed color
    def color_object
      Color.new(color)
    end

    # Check if embed has fields
    # @return [Boolean] True if has fields
    def has_fields?
      fields.any?
    end

    # Get fields
    # @return [Array<EmbedField>] Fields
    def embed_fields
      (@raw_data['fields'] || []).map { |f| EmbedField.new(f) }
    end

    # Get footer
    # @return [EmbedFooter, nil] Footer
    def embed_footer
      EmbedFooter.new(@raw_data['footer']) if @raw_data['footer']
    end

    # Get image
    # @return [EmbedImage, nil] Image
    def embed_image
      EmbedImage.new(@raw_data['image']) if @raw_data['image']
    end

    # Get thumbnail
    # @return [EmbedThumbnail, nil] Thumbnail
    def embed_thumbnail
      EmbedThumbnail.new(@raw_data['thumbnail']) if @raw_data['thumbnail']
    end

    # Get video
    # @return [EmbedVideo, nil] Video
    def embed_video
      EmbedVideo.new(@raw_data['video']) if @raw_data['video']
    end

    # Get provider
    # @return [EmbedProvider, nil] Provider
    def embed_provider
      EmbedProvider.new(@raw_data['provider']) if @raw_data['provider']
    end

    # Get author
    # @return [EmbedAuthor, nil] Author
    def embed_author
      EmbedAuthor.new(@raw_data['author']) if @raw_data['author']
    end

    # Check if embed has image or thumbnail
    # @return [Boolean] True if has media
    def has_media?
      @raw_data['image'] || @raw_data['thumbnail']
    end

    # Check if embed is empty
    # @return [Boolean] True if empty
    def empty?
      title.nil? && description.nil? && !has_fields?
    end

    # Builder class for creating embeds
    class Builder
      def initialize
        @data = {}
      end

      def title(value)
        @data['title'] = value
        self
      end

      def description(value)
        @data['description'] = value
        self
      end

      def url(value)
        @data['url'] = value
        self
      end

      def timestamp(value)
        @data['timestamp'] = value.iso8601
        self
      end

      def color(value)
        @data['color'] = value.is_a?(Color) ? value.to_i : value
        self
      end

      def field(name:, value:, inline: false)
        @data['fields'] ||= []
        @data['fields'] << { 'name' => name, 'value' => value, 'inline' => inline }
        self
      end

      def footer(text:, icon_url: nil)
        @data['footer'] = { 'text' => text }
        @data['footer']['icon_url'] = icon_url if icon_url
        self
      end

      def image(url:, proxy_url: nil, height: nil, width: nil)
        @data['image'] = { 'url' => url }
        @data['image']['proxy_url'] = proxy_url if proxy_url
        @data['image']['height'] = height if height
        @data['image']['width'] = width if width
        self
      end

      def thumbnail(url:, proxy_url: nil, height: nil, width: nil)
        @data['thumbnail'] = { 'url' => url }
        @data['thumbnail']['proxy_url'] = proxy_url if proxy_url
        @data['thumbnail']['height'] = height if height
        @data['thumbnail']['width'] = width if width
        self
      end

      def author(name:, url: nil, icon_url: nil)
        @data['author'] = { 'name' => name }
        @data['author']['url'] = url if url
        @data['author']['icon_url'] = icon_url if icon_url
        self
      end

      def build
        Embed.new(@data)
      end

      def to_h
        @data
      end
    end
  end

  # Embed field
  class EmbedField < Entity
    attribute :name, type: :string
    attribute :value, type: :string
    attribute :inline, type: :boolean, default: false

    def inline?
      inline
    end
  end

  # Embed footer
  class EmbedFooter < Entity
    attribute :text, type: :string
    attribute :icon_url, type: :string
    attribute :proxy_icon_url, type: :string
  end

  # Embed image
  class EmbedImage < Entity
    attribute :url, type: :string
    attribute :proxy_url, type: :string
    attribute :height, type: :integer
    attribute :width, type: :integer
  end

  # Embed thumbnail
  class EmbedThumbnail < Entity
    attribute :url, type: :string
    attribute :proxy_url, type: :string
    attribute :height, type: :integer
    attribute :width, type: :integer
  end

  # Embed video
  class EmbedVideo < Entity
    attribute :url, type: :string
    attribute :proxy_url, type: :string
    attribute :height, type: :integer
    attribute :width, type: :integer
  end

  # Embed provider
  class EmbedProvider < Entity
    attribute :name, type: :string
    attribute :url, type: :string
  end

  # Embed author
  class EmbedAuthor < Entity
    attribute :name, type: :string
    attribute :url, type: :string
    attribute :icon_url, type: :string
    attribute :proxy_icon_url, type: :string
  end
end
