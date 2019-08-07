class SecretsManager
    def initialize
        @default_engine="aws"
    end
    def get_engine
        @default_engine
    end
end