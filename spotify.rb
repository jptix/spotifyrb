require "rubygems"
require "ffi"

module Spotify
  module Lib
    extend FFI::Library

    ffi_lib "./lib/libspotify.so"

    API_VERSION = 1

    attach_function :sp_link_create_from_string, [:string                   ], :pointer
    attach_function :sp_link_as_string,          [:pointer, :string, :int   ], :int
    attach_function :sp_link_release,            [:pointer                  ], :void
    attach_function :sp_session_init,            [:pointer, :pointer        ], :int
    attach_function :sp_link_as_track,           [:pointer                  ], :pointer
    attach_function :sp_track_name,              [:pointer                  ], :string
    attach_function :sp_session_login,           [:pointer, :string, :string], :int
    attach_function :sp_session_process_events,  [:pointer, :pointer        ], :void
    attach_function :sp_error_message,           [:int                      ], :string

    class SessionConfig < FFI::Struct
      layout :api_version,          :int,
             :cache_location,       :pointer,
             :settings_location,    :pointer,
             :application_key,      :pointer,
             :application_key_size, :uint,
             :user_agent,           :pointer,
             :callbacks,            :pointer,
             :userdata,             :pointer
    end

    callback :logged_in,          [:pointer, :int                     ], :void
    callback :logged_out,         [:pointer                           ], :void
    callback :metadata_updated,   [:pointer                           ], :void
    callback :connection_error,   [:pointer, :int                     ], :void
    callback :message_to_user,    [:pointer, :string                  ], :void
    callback :notify_main_thread, [:pointer                           ], :void
    callback :music_delivery,     [:pointer, :pointer, :pointer, :int ], :int
    callback :play_token_lost,    [:pointer                           ], :void
    callback :log_message,        [:pointer, :string                  ], :void

    class SessionCallbacks < FFI::Struct
      layout :logged_in,          :logged_in,
             :logged_out,         :logged_out,
             :metadata_updated,   :metadata_updated,
             :connection_error,   :connection_error,
             :message_to_user,    :message_to_user,
             :notify_main_thread, :notify_main_thread,
             :music_delivery,     :music_delivery,
             :play_token_lost,    :play_token_lost,
             :log_message,        :log_message
    end
  end # Lib

  class Client

    class Error < StandardError; end

    attr_accessor :verbose, :key_file, :cache_location, :settings_location

    def initialize
      @verbose           = false
      @key_file          = nil
      @callbacks         = {}
      @cache_location    = File.dirname(__FILE__)
      @settings_location = File.dirname(__FILE__)


      yield self if block_given?
    end

    #
    # callbacks
    #

    def on_login(&blk)
      @callbacks[:on_login] = blk
    end

    def on_logout(&blk)
      @callbacks[:on_logout] = blk
    end

    #
    # login (needs premium user)
    #


    def login(user, pass)
      create_config
      create_callbacks
      create_session

      check_error Spotify::Lib.sp_session_login(@session_ptr, user, pass)
    end

    #
    # start the run loop
    #

    def run_loop
      sleep_ptr = FFI::MemoryPointer.new :int

      loop do
        Spotify::Lib.sp_session_process_events(@session_ptr, sleep_ptr)
        sleep(sleep_ptr.read_int/1000)
      end
    end

    private

    def create_config
      raise "must set Client#key_file=" unless @key_file
      key     = File.read(@key_file)
      @config = Spotify::Lib::SessionConfig.new

      @config[:api_version]          = Spotify::Lib::API_VERSION
      @config[:cache_location]       = FFI::MemoryPointer.from_string(@cache_location)
      @config[:settings_location]    = FFI::MemoryPointer.from_string(@settings_location)
      @config[:application_key]      = FFI::MemoryPointer.from_string(key)
      @config[:application_key_size] = key.size
      @config[:user_agent]           = FFI::MemoryPointer.from_string("Spotify Url Checker")
    end

    def create_callbacks
      session_callbacks = Spotify::Lib::SessionCallbacks.new
      session_callbacks[:logged_in] = method(:logged_in).to_proc
      session_callbacks[:logged_out] = method(:logged_out).to_proc

      @config[:callbacks] = session_callbacks.to_ptr
    end

    def create_session
      session_ptr_ptr = FFI::MemoryPointer.new(4)
      check_error Spotify::Lib.sp_session_init(@config, session_ptr_ptr)

      @session_ptr = session_ptr_ptr.get_pointer(0)
    end

    def logged_in(session, error)
      log :logged_in, session, error
      check_error error

      invoke_callback :on_login, session, error
    end

    def logged_out(session)
      log :logged_out, session

      invoke_callback :on_logout, session
    end

    def check_error(error_code)
      if error_code != 0
        raise Error, Spotify::Lib.sp_error_message(error_code)
      end
    end

    def log(*args)
      puts "#{self} @ #{Time.now} :: #{args.inspect}" if @verbose
    end

    def invoke_callback(callback, *args)
      cb = @callbacks[callback]
      cb.call(*args) if cb
    end

  end # Client
end # Spotify

if __FILE__ == $0
  user, pass = ARGV[0], ARGV[1]

  client          = Spotify::Client.new
  client.verbose  = true
  client.key_file = "spotify_appkey.key"

  client.login ARGV[0], ARGV[1]

  client.run_loop
end




