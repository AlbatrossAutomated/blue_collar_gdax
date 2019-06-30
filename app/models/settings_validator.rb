# frozen_string_literal: true

class SettingsValidator
  class << self
    def validate
      validate_coverage
    end

    def validate_coverage
      return if BotSettings::COVERAGE.between?(0.01, 1.0)

      msg = "Coverage invalid: Must be in the range 0.01 - 1.0"
      raise CriticalError, msg
    end
  end
end
