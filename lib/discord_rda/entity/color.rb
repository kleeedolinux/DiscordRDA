# frozen_string_literal: true

module DiscordRDA
  # Represents a Discord color.
  # Provides conversion between RGB, hex, and integer representations.
  #
  # @example Creating colors
  #   Color.new(0xFF5733)           # From integer
  #   Color.from_rgb(255, 87, 51)    # From RGB
  #   Color.from_hex('#FF5733')      # From hex string
  #   Color.teal                     # Named color
  #
  class Color
    # Default Discord colors
    DEFAULTS = {
      default: 0,
      white: 0xFFFFFF,
      aqua: 0x1ABC9C,
      green: 0x57F287,
      blue: 0x3498DB,
      yellow: 0xFEE75C,
      purple: 0x9B59B6,
      luminous_vivid_pink: 0xE91E63,
      gold: 0xF1C40F,
      orange: 0xE67E22,
      red: 0xED4245,
      grey: 0x95A5A6,
      navy: 0x34495E,
      dark_aqua: 0x11806A,
      dark_green: 0x1F8B4C,
      dark_blue: 0x206694,
      dark_purple: 0x71368A,
      dark_vivid_pink: 0xAD1457,
      dark_gold: 0xC27C0E,
      dark_orange: 0xA84300,
      dark_red: 0x992D22,
      dark_grey: 0x979C9F,
      darker_grey: 0x7F8C8D,
      light_grey: 0xBCC0C0,
      dark_navy: 0x2C3E50,
      blurple: 0x5865F2,
      greyple: 0x99AAB5,
      dark_but_not_black: 0x2C2F33,
      not_quite_black: 0x23272A
    }.freeze

    # @return [Integer] The color value
    attr_reader :value

    class << self
      # Create from RGB values
      # @param r [Integer] Red (0-255)
      # @param g [Integer] Green (0-255)
      # @param b [Integer] Blue (0-255)
      # @return [Color] New color
      def from_rgb(r, g, b)
        new((r.to_i << 16) | (g.to_i << 8) | b.to_i)
      end

      # Create from hex string
      # @param hex [String] Hex string (#RRGGBB or RRGGBB)
      # @return [Color] New color
      def from_hex(hex)
        hex = hex.to_s.delete_prefix('#')
        new(hex.to_i(16))
      end

      # Create from HSL values
      # @param h [Float] Hue (0-360)
      # @param s [Float] Saturation (0-1)
      # @param l [Float] Lightness (0-1)
      # @return [Color] New color
      def from_hsl(h, s, l)
        h = h.to_f / 360.0
        s = s.to_f
        l = l.to_f

        r, g, b = if s == 0
                    [l, l, l]
                  else
                    q = l < 0.5 ? l * (1 + s) : l + s - l * s
                    p = 2 * l - q
                    [hue_to_rgb(p, q, h + 1.0 / 3),
                     hue_to_rgb(p, q, h),
                     hue_to_rgb(p, q, h - 1.0 / 3)]
                  end

        from_rgb((r * 255).round, (g * 255).round, (b * 255).round)
      end

      # Generate random color
      # @return [Color] Random color
      def random
        new(rand(0xFFFFFF))
      end

      # Named color methods
      DEFAULTS.each do |name, value|
        define_method(name) { new(value) }
      end

      private

      def hue_to_rgb(p, q, t)
        t += 1 if t < 0
        t -= 1 if t > 1
        return p + (q - p) * 6 * t if t < 1.0 / 6
        return q if t < 1.0 / 2
        return p + (q - p) * (2.0 / 3 - t) * 6 if t < 2.0 / 3
        p
      end
    end

    # Initialize with a color value
    # @param value [Integer] Color value (0-0xFFFFFF)
    def initialize(value = 0)
      @value = value.to_i & 0xFFFFFF
    end

    # Get red component
    # @return [Integer] Red (0-255)
    def r
      (@value >> 16) & 0xFF
    end
    alias red r

    # Get green component
    # @return [Integer] Green (0-255)
    def g
      (@value >> 8) & 0xFF
    end
    alias green g

    # Get blue component
    # @return [Integer] Blue (0-255)
    def b
      @value & 0xFF
    end
    alias blue b

    # Get RGB array
    # @return [Array<Integer>] RGB values
    def rgb
      [r, g, b]
    end

    # Get hex string
    # @param prefix [Boolean] Include # prefix
    # @return [String] Hex string
    def to_hex(prefix: true)
      hex = @value.to_s(16).upcase.rjust(6, '0')
      prefix ? "##{hex}" : hex
    end

    # Convert to RGB tuple string
    # @return [String] RGB string
    def to_rgb_string
      "rgb(#{r}, #{g}, #{b})"
    end

    # Get integer value
    # @return [Integer] Color value
    def to_i
      @value
    end

    # Convert to decimal color string (for Discord)
    # @return [String] Decimal string
    def to_s
      @value.to_s
    end

    # Check if color is valid (non-zero)
    # @return [Boolean] True if has color
    def valid?
      @value > 0
    end

    # Check if color is the default (0)
    # @return [Boolean] True if default
    def default?
      @value == 0
    end

    # Get brightness (0-255)
    # @return [Integer] Brightness
    def brightness
      (r * 299 + g * 587 + b * 114) / 1000
    end

    # Check if color is light (brightness > 128)
    # @return [Boolean] True if light
    def light?
      brightness > 128
    end

    # Check if color is dark (brightness <= 128)
    # @return [Boolean] True if dark
    def dark?
      brightness <= 128
    end

    # Blend with another color
    # @param other [Color] Other color
    # @param ratio [Float] Blend ratio (0-1)
 # @return [Color] Blended color
    def blend(other, ratio = 0.5)
      r = (self.r * (1 - ratio) + other.r * ratio).round
      g = (self.g * (1 - ratio) + other.g * ratio).round
      b = (self.b * (1 - ratio) + other.b * ratio).round
      self.class.from_rgb(r, g, b)
    end

    # Darken the color
    # @param amount [Float] Amount to darken (0-1)
    # @return [Color] Darkened color
    def darken(amount = 0.2)
      blend(self.class.new(0), amount)
    end

    # Lighten the color
    # @param amount [Float] Amount to lighten (0-1)
    # @return [Color] Lightened color
    def lighten(amount = 0.2)
      blend(self.class.new(0xFFFFFF), amount)
    end

    # Get complementary color
    # @return [Color] Complementary color
    def complementary
      self.class.from_rgb(255 - r, 255 - g, 255 - b)
    end

    # Check equality
    # @param other [Object] Other object
    # @return [Boolean] True if equal
    def ==(other)
      other.is_a?(Color) && @value == other.value
    end

    # Hash code
    # @return [Integer] Hash code
    def hash
      @value.hash
    end

    # Inspect
    # @return [String] Inspect string
    def inspect
      "#<Color #{to_hex}>"
    end
  end
end
