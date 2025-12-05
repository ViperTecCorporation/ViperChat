# Rack 3 removes Rack::File in favor of Rack::Files.
# Some middleware (e.g., rack-mini-profiler) still references Rack::File.
# Provide a backward-compatible alias to avoid NameError 500s on /mini-profiler-resources.
unless defined?(Rack::File) && Rack.const_defined?(:File)
  Rack::File = Rack::Files
end
