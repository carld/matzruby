#
#   tkafter.rb : methods for Tcl/Tk after command
#                     1998/06/23 by Hidetoshi Nagai <nagai@ai.kyutech.ac.jp>
#
require 'tk'

class TkAfter
  include TkCore
  extend TkCore

  Tk_CBID = [0]
  Tk_CBTBL = {}

  INTERP._invoke("proc", "rb_after", "args", "ruby [format \"TkAfter.callback %%Q!%s!\" $args]")

  ###############################
  # class methods
  ###############################
  def TkAfter.callback(arg)
    @after_id = nil
    arg = Array(tk_split_list(arg))
    obj_id = arg.shift
    return nil if Tk_CBTBL[obj_id] == nil; # canceled
    ret = _get_eval_string(Tk_CBTBL[obj_id].do_callback(*arg))
    Tk_CBTBL[obj_id].set_next_callback(*arg)
    ret
  end

  def TkAfter.info
    tk_call('after', 'info').split(' ').filter{|id|
      ret = Tk_CBTBL.find{|key,val| val.after_id == id}
      (ret == nil)? id: ret[1]
    }
  end

  ###############################
  # instance methods
  ###############################
  def do_callback(*args)
    @current_proc.call(*args)
  end

  def set_callback(sleep, args=nil)
    @after_script = "rb_after #{@id} #{_get_eval_string(args)}"
    @after_id = tk_call('after', sleep, @after_script)
    @current_script = [sleep, @after_script]
  end

  def set_next_callback(*args)
    if @running == false || @proc_max == 0 || @do_loop == 0
      Tk_CBTBL[@id] = nil ;# for GC
      return
    end
    if @current_pos >= @proc_max
      if @do_loop < 0 || (@do_loop -= 1) > 0
	@current_pos = 0
      else
	Tk_CBTBL[@id] = nil ;# for GC
	return
      end
    end

    @current_args = args

    if @sleep_time.kind_of? Proc
      sleep = @sleep_time.call(*args)
    else
      sleep = @sleep_time
    end
    @current_sleep = sleep

    cmd, *cmd_args = @loop_proc[@current_pos]
    @current_pos += 1
    @current_proc = cmd

    if cmd_args[0].kind_of? Proc
      #c = cmd_args.shift
      #cb_args = c.call(*(cmd_args + args))
      cb_args = cmd_args[0].call(*args)
    else
      cb_args = cmd_args
    end

    set_callback(sleep, cb_args)
  end

  def initialize(*args)
    @id = format("a%.4d", Tk_CBID[0])
    Tk_CBID[0] += 1

    @init_sleep=0
    @init_proc=nil
    @init_args=[]

    @current_script = []
    @current_proc = nil
    @current_args = nil

    @sleep_time = 0
    @current_sleep = 0
    @loop_exec = 0
    @do_loop = 0
    @loop_proc = []
    @proc_max = 0
    @current_pos = 0

    @after_id = nil
    @after_script = nil

    set_procs(*args) if args != []

    @running = false
  end

  attr :after_id
  attr :after_script
  attr :current_proc
  attr :current_sleep

  attr_accessor :loop_exec

  def get_procs
    [@init_sleep, @init_proc, @init_args, @sleep_time, @loop_exec, @loop_proc]
  end

  def current_status
    [@running, @current_sleep, @current_proc, @current_args, @do_loop]
  end

  def running?
    @running
  end

  def loop_rest
    @do_loop
  end

  def loop_rest=(rest)
    @do_loop = rest
  end

  def set_procs(interval, loop_exec, *procs)
    if !interval == 'idle' \
       && !interval.kind_of?(Integer) && !interval.kind_of?(Proc)
      fail format("%s need to be Integer or Proc", interval.inspect)
    end
    @sleep_time = interval

    @loop_proc = []
    procs.each{|e|
      if e.kind_of? Proc
	@loop_proc.push([e])
      else
	@loop_proc.push(e)
      end
    }
    @proc_max = @loop_proc.size
    @current_pos = 0

    @do_loop = 0
    if loop_exec
      if loop_exec.kind_of?(Integer) && loop_exec < 0
	@loop_exec = -1
      elsif loop_exec == nil || loop_exec == false || loop_exec == 0
	@loop_exec = 1
      else
	if not loop_exec.kind_of?(Integer)
	  fail format("%s need to be Integer", loop_exec.inspect)
	end
	@loop_exec = loop_exec
      end
      @do_loop = @loop_exec
    end

    self
  end

  def add_procs(*procs)
    procs.each{|e|
      if e.kind_of? Proc
	@loop_proc.push([e])
      else
	@loop_proc.push(e)
      end
    }
    @proc_max = @loop_proc.size

    self
  end

  def start(sleep=0, init_proc=nil, *init_args)
    return nil if @running

    Tk_CBTBL[@id] = self
    @do_loop = @loop_exec
    @current_pos = 0

    if !sleep == 'idle' && !sleep.kind_of?(Integer)
      fail format("%s need to be Integer", sleep.inspect)
    end

    @init_proc = init_proc
    @init_args = init_args
    @current_sleep = @init_sleep = sleep
    @running = true
    if init_proc
      if not init_proc.kind_of? Proc
	fail format("%s need to be Proc", init_proc.inspect)
      end
      @current_proc = init_proc
      set_callback(sleep, init_args)
    else
      set_next_callback(*init_args)
    end

    self
  end

  def restart
    cancel if @running
    start(@init_sleep, @init_proc, @init_args)
  end

  def cancel
    @running = false
    tk_call 'after', 'cancel', @after_id if @after_id
    @after_id = nil
    Tk_CBTBL[@id] = nil ;# for GC
    self
  end
  alias stop cancel

  def continue(wait=nil)
    sleep, cmd = @current_script
    return nil if cmd == nil || @running == true
    if wait
      if not wait.kind_of? Integer
	fail format("%s need to be Integer", wait.inspect)
      end
      sleep = wait
    end
    Tk_CBTBL[@id] = self
    @running = true
    @after_id = tk_call('after', sleep, cmd)
    self
  end

  def skip
    return nil if @running == false
    cancel
    Tk_CBTBL[@id] = self
    @running = true
    set_next_callback(@current_args)
    self
  end

  def info
    if @after_id
      inf = tk_split_list(tk_call('after', 'info', @after_id))
      [Tk_CBTBL[inf[0][1]], inf[1]]
    else
      nil
    end
  end
end
