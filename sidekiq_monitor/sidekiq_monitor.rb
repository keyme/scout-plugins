$VERBOSE=false
class SidekiqMonitor < Scout::Plugin
  needs 'redis', 'sidekiq'

  OPTIONS = <<-EOS
  host:
    name: Host
    notes: Redis hostname (or IP address) to pass to the client library, ie where redis is running.
    default: localhost
  port:
    name: Port
    notes: Redis port to pass to the client library.
    default: 6379
  db:
    name: Database
    notes: Redis database ID to pass to the client library.
    default: 0
  username:
    name: RedisToGo Username
    notes: If you're using RedisToGo.
    attributes: advanced
  password:
    name: Password
    notes: If you're using Redis' username/password authentication.
    attributes: password
  queues:
    name: Queues
    notes: Comma separated list of queues to monitor (* for all).
    default: *
  namespace:
    name: Namespace
    notes: Redis namespace used for Sidekiq keys
  EOS

  def build_report
    protocol = 'redis://'
    auth = [option(:username), option(:password)].compact.join(':')
    path = "#{option(:host)}:#{option(:port)}/#{option(:db)}"

    url = protocol
    url += auth + '@' if auth && auth != ':'
    url += path

    Sidekiq.configure_client do |config|
      config.redis = { :url => url, :namespace => option(:namespace) }
    end

    begin
      stats = Sidekiq::Stats.new
      workers = Sidekiq::Workers.new

      [:enqueued, :failed, :processed].each do |nsym|
        value = stats.send(nsym)
        report(nsym => value)
        counter("#{nsym}_per_minute".to_sym, value, :per => :minute)
      end

      worker_size = workers.size
      report(:busy_workers => worker_size)
      counter(:busy_workers_per_minute, worker_size, :per => :minute)

      queues = option(:queues)
      queues = (queues=='*') ? '*' : queues.split(',')
      stats.queues.each do |q, v|
        next if queues != '*' and !queues.include? q.to_s
        report("#{q}_enqueued" => v)
        counter("#{q}_enqueued_per_minute".to_sym, v, :per => :minute)
      end
    end
  rescue Exception => e
    return error( "Could not connect to Redis.",
                  "#{e.message} \n\n#{e.backtrace}\n\nMake certain you've specified the correct host and port, DB, username, and password, and that Redis is accepting connections." )
  end
end

