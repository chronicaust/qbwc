class QBWC::ActiveRecord::Session < QBWC::Session
  class QbwcSession < ActiveRecord::Base
    belongs_to :account
    belongs_to :db_user, primary_key: :email, foreign_key: :user, class_name: "User"

    attr_accessible :company, :ticket, :user, :account_id unless Rails::VERSION::MAJOR >= 4

    after_save_commit -> do
      Rails.logger.info "Broadcasting QB Session Event for Account #{account_id} and Session ID #{id} progress #{progress}%"
      broadcast_prepend_to("qb_web_connector_session", partial: "/events/qb_web_connector_session", locals: { qb_session: self }, target: "progressDivScript")
    end

    before_destroy -> do
      self.progress = 0
      Rails.logger.info "Broadcasting QB Session Event for Account #{account_id} and Session ID #{id} progress #{progress}%"
      broadcast_prepend_to("qb_web_connector_session", partial: "/events/qb_web_connector_session", locals: { qb_session: self }, target: "progressDivScript")
    end
  end

  def self.get(ticket)
    session = QbwcSession.find_by_ticket(ticket)
    self.new(session) if session
  end

  def initialize(session_or_user = nil, company = nil, ticket = nil, account_id = nil)
    if session_or_user.is_a? QbwcSession
      @session = session_or_user
      # Restore current job from saved one on QbwcSession
      @current_job = QBWC.get_job_by_name_and_account(@session.current_job, @session.account_id) if @session.current_job
      # Restore pending jobs from saved list on QbwcSession
      @pending_jobs = @session.pending_jobs.split(',').map { |job_name| QBWC.get_job_by_name_and_account(job_name, @session.account_id) }.select { |job| ! job.nil? }
      super(@session.user, @session.company, @session.ticket, @session.account_id)
    else
      super
      @session = QbwcSession.new
      @session.user = self.user
      @session.company = self.company
      @session.ticket = self.ticket
      @session.account_id = self.account_id
      self.save
      @session
    end
  end

  def save
    @session.pending_jobs = pending_jobs.map(&:name).join(',')
    @session.current_job = current_job.try(:name)
    @session.save
    super
  end

  def destroy
    @session.destroy
    super
  end

  [:error, :progress, :iterator_id].each do |method|
    define_method method do
      @session.send(method)
    end
    define_method "#{method}=" do |value|
      @session.send("#{method}=", value)
    end
  end
  protected :progress=, :iterator_id=, :iterator_id

end
