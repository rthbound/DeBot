require "core_ext/thread"
require "core_ext/io"
require "thread/queue"

require "./message"

module IRC
  class Reader
    delegate join, @th

    def initialize socket, queue
      @socket = socket
      pipe, @pipe = IO.pipe
      @th = Thread.new(self) do |reader|
        loop do
          begin
            io = IO.select([socket, pipe])

            if io == pipe
              break if pipe.gets == "stop\n"
              next
            end

            line = socket.gets
            if line
              puts "< #{line}"
              message = Message.from(line)
              queue << message if message
            end
          rescue e : Errno
            raise e unless e.errno == Errno::EINTR
          end
        end
      end
      @th.name = "Reader"
    end

    def stop
      @pipe.puts "stop"
      @pipe.close
      @socket.close
    end
  end

  class Sender
    delegate join, @th

    def initialize socket, queue
      @queue = queue
      @th = Thread.new(self) do |sender|
        loop do
          message = queue.shift
          if message.is_a? String
            puts "> #{message}"
            socket.puts message
          elsif message == :stop
            break
          end
        end
      end
      @th.name = "Sender"
    end

    def stop
      @queue << :stop
    end
  end

  class Processor
    record Job, message, handler

    delegate join, @th

    def initialize id, pool, queue
      @th = Thread.new(self) do |processor|
        loop do
          work = queue.shift
          if work.is_a? Message
            pool.handlers.each do |handler|
              queue << Job.new(work, handler)
            end
          elsif work.is_a? Job
            work.handler.call(work.message)
          elsif work == :stop
            break
          end
        end
      end
      @th.name = "Processor #{id}"
    end
  end

  class ProcessorPool
    getter queue
    getter handlers

    def initialize @size
      @queue = Queue(Processor::Job|Message|Symbol).new
      @processors = Array.new(@size) {|id| Processor.new(id+1, self, queue) }
      @handlers = Array(Message ->).new
    end

    def handle(&handler : Message ->)
      @handlers << handler
      handler
    end

    def on *types, &handler : Message ->
      handle do |message|
        handler.call(message) if types.includes? message.type
      end
    end

    def stop
      @size.times do
        @queue << :stop
      end
    end

    def join
      @processors.each &.join
    end
  end
end