class SecretsManager
    def initialize
        @default_engine="aws"
        @environment="production"
    end
    def get_engine
        @default_engine
    end    
    attr_accessor :environment
    attr_accessor :repository
end