class QBWC::Job

  attr_reader :name, :company, :worker_class, :account_id, :qb_workable

  def initialize(name, enabled, company, worker_class, requests = [], data = nil, account_id = nil, qb_workable = nil)
    @name = name
    @enabled = enabled
    @company = company || QBWC.company_file_path
    @worker_class = worker_class
    @data = data
    @account_id = account_id
    @qb_workable = qb_workable

    default_key = [nil, company]
    requests = [requests].compact unless Hash === requests || Array === requests
    requests = { default_key => requests } unless Hash === requests || requests.empty?
    @requests = requests

    @request_index = { default_key => 0 }
  end

  def account_id
    @account_id
  end

  def qb_workable
    @qb_workable
  end

  def set_qb_workable=(q)
    @qb_workable = q
  end


  def worker
    worker_class.constantize.new
  end

  def process_response(qbxml_response, response, session, advance)
    QBWC.logger.info "Processing response."
    request_list = requests(session)
    completed_request = request_list[request_index(session)] if request_list
    QBWC.logger.info "Processing response. - advance: #{advance}"
    advance_next_request(session) if advance
    QBWC.logger.info "Job '#{name}' received response: '#{qbxml_response}'." if QBWC.log_requests_and_responses
    worker.handle_response(response, session, self, completed_request, data)
  end

  def advance_next_request(session)
    new_index = request_index(session) + 1
    QBWC.logger.info "Job '#{name}' advancing to request #'#{new_index}'."
    @request_index[session.key] = new_index
  end

  def enable
    self.enabled = true
  end

  def disable
    self.enabled = false
  end

  def pending?(session)
    if !enabled?
      QBWC.logger.info "Job '#{name}' not enabled."
      return false
    end
    sr = worker.should_run?(self, session, @data)
    QBWC.logger.info "Job '#{name}' should_run?: #{sr}."
    return sr
  end

  def fast_pending?(session)
    sr = worker.should_run?(self, session, @data)
    QBWC.logger.info "Job '#{name}' should_run?: #{sr}."
    return sr
  end

  
  def enabled?
    @enabled
  end

  def requests(session)
    secondary_key = session.key.dup
    secondary_key[0] = nil # username = nil
    result = nil
    [session.key, secondary_key].each do |k|
      result ||= (@requests || {})[k]
    end
    result
  end

  def set_requests(session, requests)
    @requests ||= {}
    @requests[session.key] = requests
  end

  def requests=(requests)
    @requests = requests
  end

  def data
    if @data.present? && @data.is_a?(Array) && [Hash, JSON].include?(@data.first.class)
      @data&.map(&:with_indifferent_access)
    else
      @data
    end
  end

  def data=(d)
    @data = d
  end

  def request_index(session)
    @request_index[session.key] || 0
  end

  def requests_provided_when_job_added
    @requests_provided_when_job_added
  end

  def requests_provided_when_job_added=(value)
    @requests_provided_when_job_added = value
  end

  def next_request(session = QBWC::Session.get)
    reqs = requests session

    # Generate and save the requests to run when starting the job.
    if (reqs.nil? || reqs.empty?) && ! self.requests_provided_when_job_added
      greqs = worker.requests(self, session, @data)
      greqs = [greqs] unless greqs.nil? || greqs.is_a?(Array)
      set_requests session, greqs
      reqs = requests session
    end

    QBWC.logger.info("Requests available are '#{reqs}'.") if QBWC.log_requests_and_responses
    ri = request_index session
    QBWC.logger.info("Request index is '#{ri}'.")
    return nil if ri.nil? || reqs.nil? || ri >= reqs.length
    nr = reqs[ri]
    QBWC.logger.info("Next request is '#{nr}'.") if QBWC.log_requests_and_responses
    return QBWC::Request.new(nr) if nr
  end
  alias :next :next_request  # Deprecated method name 'next'

  def reset
    @request_index = {}
    @requests = {} unless self.requests_provided_when_job_added
  end

end
