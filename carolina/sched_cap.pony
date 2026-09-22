// Fly's production VM is one shared CPU. The Pony runtime otherwise starts
// one scheduler thread per host core before `Main` runs, which dominates
// cold start on a machine that only has one CPU.

primitive SchedCap
  """
  Scheduler threads for the production process. Matches `fly.toml` `cpus = 1`.
  """
  fun threads(): U32 => 1
