# frozen_string_literal: true

# Copyright 2019 OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

module OpenTelemetry
  module SDK
    module Trace
      module Export

        # Singleton used to find the "dispatcher" of the current process,
        # i.e. the web server (Puma, Unicorn) or job processor (Sidekiq, Resque)
        # used to execute code. Detection is done on a best-effort basis.
        # It is recommended to set explicitly set the OTEL_DISPATCHER
        # environment variable.
        module DispatcherDetector
          extend self

          DISPATCHERS = %i[ delayed_job
                            resque
                            sidekiq
                            puma
                            passenger
                            rainbows
                            unicorn
                            torquebox
                            trinidad
                            glassfish
                            thin
                            mongrel
                            litespeed
                            webrick
                            fastcgi ].freeze

          def dispatcher
            @dispatcher ||= env_dispatcher || detect_dispatcher
          end

          private

          def env_dispatcher
            env = ENV['OTEL_DISPATCHER']&.strip&.to_sym
            return unless env

            dispatcher = DISPATCHERS.detect { |d| d == env }
            if dispatcher
              OpenTelemetry.logger.info("Dispatcher :#{dispatcher} set by OTEL_DISPATCHER environment variable")
            else
              OpenTelemetry.logger.warn("OTEL_DISPATCHER \"#{dispatcher}\" not valid")
            end
            dispatcher
          end

          def detect_dispatcher
            dispatcher = DISPATCHERS.detect { |d| send :"detect_#{d}" }
            OpenTelemetry.logger.info("Dispatcher :#{dispatcher} auto-detected") if dispatcher
            dispatcher
          end

          def detect_delayed_job
            $0 =~ /delayed_job$/ || (File.basename($0) == 'rake' && ARGV.include?('jobs:work'))
          end

          def detect_fastcgi
            defined?(::FCGI)
          end

          def detect_glassfish
            defined?(::JRuby) &&
                (((com.sun.grizzly.jruby.rack.DefaultRackApplicationFactory rescue nil) &&
                    defined?(com::sun::grizzly::jruby::rack::DefaultRackApplicationFactory)) ||
                    (defined?(JRuby::Rack::VERSION) && defined?(::GlassFish::Server)))
          end

          def detect_litespeed
            caller.pop =~ %r{fcgi-bin/RailsRunner\.rb}
          end

          def detect_mongrel
            defined?(::Mongrel) && defined?(::Mongrel::HttpServer)
          end

          def detect_passenger
            defined?(::PhusionPassenger)
          end

          def detect_puma
            defined?(::Puma) && File.basename($0) == 'puma'
          end

          def detect_rainbows
            defined?(::Rainbows) && defined?(::Rainbows::HttpServer) && object_loaded?(::Rainbows::HttpServer)
          end

          def detect_resque
            resque_rake      = executable == 'rake' && ARGV.include?('resque:work') && (ENV['QUEUE'] || ENV['QUEUES'])
            resque_pool_rake = executable == 'rake' && ARGV.include?('resque:pool')
            resque_pool_exec = executable == 'resque-pool' && defined?(::Resque::Pool)

            defined?(::Resque) && (resque_rake || resque_pool_exec || resque_pool_rake)
          end

          def detect_sidekiq
            defined?(::Sidekiq) && File.basename($0) == 'sidekiq'
          end

          def detect_thin
            defined?(::Thin) && defined?(::Thin::Server) && object_loaded?(::Thin::Server)
          end

          def detect_torquebox
            defined?(::JRuby) && (org.torquebox::TorqueBox rescue nil)
          end

          def detect_trinidad
            defined?(::JRuby) && defined?(JRuby::Rack::VERSION) && defined?(::Trinidad::Server)
          end

          def detect_unicorn
            defined?(::Unicorn) && defined?(::Unicorn::HttpServer) && object_loaded?(::Unicorn::HttpServer)
          end

          def detect_webrick
            defined?(::WEBrick) && defined?(::WEBrick::VERSION)
          end

          def object_loaded?(klass)
            return true unless object_space_supported?

            ObjectSpace.each_object(klass) {|_| return true }
            false
          end

          def object_space_supported?
            if defined?(::JRuby) && JRuby.respond_to?(:runtime)
              JRuby.runtime.is_object_space_enabled
            else
              defined?(::ObjectSpace)
            end
          end

          def executable
            File.basename($0)
          end
        end
      end
    end
  end
end
