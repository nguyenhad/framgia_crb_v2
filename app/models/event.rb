class Event < ActiveRecord::Base
  include SharedMethods
  require "chatwork"

  acts_as_paranoid

  after_create :send_notify
  before_destroy :send_email_delete_no_repeat_event
  before_save :default_title, if: "title.blank?"

  ATTRIBUTES_PARAMS = [:title, :description, :status, :color, :all_day,
    :repeat_type, :repeat_every, :user_id, :calendar_id, :start_date,
    :finish_date, :start_repeat, :end_repeat, :exception_type, :exception_time,
    :place_id, :name_place, attendees_attributes: [:id, :email, :_destroy, :user_id],
    repeat_ons_attributes: [:id, :days_of_week_id, :_destroy],
    notification_events_attributes: [:id, :notification_id, :_destroy]]

  has_many :attendees, dependent: :destroy
  has_many :users, through: :attendees
  has_many :repeat_ons, dependent: :destroy
  has_many :days_of_weeks, through: :repeat_ons
  has_many :event_exceptions, class_name: Event.name, foreign_key: :parent_id,
    dependent: :destroy

  has_many :notification_events, dependent: :destroy
  has_many :notifications, through: :notification_events

  belongs_to :calendar
  belongs_to :owner, class_name: User.name, foreign_key: :user_id
  belongs_to :event_parent, class_name: Event.name, foreign_key: :parent_id
  belongs_to :place

  validates :start_date, presence: true
  validates :finish_date, presence: true

  delegate :name, to: :owner, prefix: :owner, allow_nil: true
  delegate :name , to: :calendar, prefix: true, allow_nil: true

  enum exception_type: [:delete_only, :delete_all_follow, :edit_only,
    :edit_all_follow, :edit_all]

  enum repeat_type: [:daily, :weekly, :monthly, :yearly]

  accepts_nested_attributes_for :attendees, allow_destroy: true
  accepts_nested_attributes_for :notification_events, allow_destroy: true
  accepts_nested_attributes_for :repeat_ons, allow_destroy: true

  scope :my_events, ->user_id do
    where("finish_time between ? and ? and user_id = ?",
      Date.today.beginning_of_week, Date.today.end_of_week, user_id)
  end

  scope :in_calendars, ->calendar_ids do
    where "calendar_id IN (?)", calendar_ids
  end

  scope :upcoming_event, ->calendar_id do
    where("start_date >= ? AND calendar_id IN (?)", DateTime.now, calendar_id).
      order start_date: :asc
  end

  scope :reject, ->event_id do
    where("id != ? AND (parent_id IS NULL OR parent_id != ?)", event_id, event_id)
  end

  scope :no_repeats, ->{where repeat_type: nil}
  scope :has_exceptions, ->{where.not exception_type: nil}
  scope :exception_edits, ->id do
    where "parent_id = ? AND exception_type IN (?)", id, [2, 3]
  end
  scope :after_date, ->date{where "start_date > ?", date}
  scope :follow_pre_nearest, ->start_date do
    where "start_date < ? AND
      (exception_type = ? OR old_exception_type = ?)",start_date,
      Event.exception_types[:edit_all_follow],
      Event.exception_types[:edit_all_follow]
  end
  scope :google_events, ->{where "parent_id IS NULL AND google_event_id IS NOT NULL"}

  scope :deleted_event_google, ->calendar_ids do
    where "calendar_id in (?) AND google_event_id IS NOT NULL", calendar_ids
  end

  scope :not_delete_only, -> do
    where.not("exception_type = ?",Event.exception_types[:delete_only])
  end

  scope :old_exception_type_not_null, ->{where.not old_exception_type: nil}

  scope :in_range, ->start_date, end_date do
    where "start_date >= ? AND finish_date <= ?",start_date, end_date
  end

  scope :old_exception_edit_all_follow, -> do
    where "old_exception_type = ?", Event.exception_types[:edit_all_follow]
  end

  scope :events_in_place, ->calendar_id, name_place do
    where "calendar_id = ? AND name_place = ?", calendar_id, name_place
  end

  class << self
    def event_exception_at_time exception_type, start_time, end_time
      find_by "exception_type IN (?) and exception_time >= ? and exception_time <= ?",
        exception_type, start_time, end_time
    end

    def find_with_exception exception_time
      find_by "exception_type IN (?) and exception_time = ?",
        [Event.exception_types[:delete_only],
        Event.exception_types[:delete_all_follow]], exception_time
    end

    def event_days
      Event.pluck("DISTINCT role")
    end
  end

  Event.repeat_types.keys.each do |repeat_type|
    define_method "repeat_#{repeat_type}?" do
      self.send "#{repeat_type}?"
    end
  end

  def parent?
    parent_id.blank?
  end

  def json_data user_id
    {
      id: Base64.encode64(id.to_s + "-" + start_date.to_s),
      title: title,
      start_date: format_datetime(start_date),
      finish_date: format_datetime(finish_date),
      start_repeat: format_date(start_date),
      end_repeat: format_date(end_repeat),
      color_id: calendar.get_color(user_id),
      calendar: calendar.name,
      all_day: all_day,
      repeat_type: repeat_type,
      repeat: load_repeat_data,
      exception_type: exception_type,
      parent_id: parent_id,
      exception_time: exception_time,
      event_id: id,
      name_place: name_place,
      place_id: place_id
    }
  end

  def is_diff_between_start_and_finish_date?
    start_date.to_date != finish_date.to_date
  end

  def exist_repeat?
    repeat_type.present? || event_parent.present?
  end

  def old_exception_edit_all_follow?
    self.old_exception_type == Event.exception_types[:edit_all_follow]
  end

  private
  def default_title
    self.title = I18n.t "events.notification.title_default"
  end

  def format_time datetime
    datetime.try :strftime, Settings.event.format_time
  end

  def load_repeat_data
    if repeat_type == 1
      repeat = Settings.event.repeat_daily
    elsif repeat_type == 2
      repeat = (repeat_ons.pluck :repeat_on).compact
    else
      nil
    end
  end

  def send_notify
    if exception_type.nil?
      attendees.each do |attendee|
        argv = {event_id: id, user_id: attendee.user_id, current_user_id: user_id}
        EmailWorker.perform_async argv
      end
    elsif self.delete_only? || self.delete_all_follow?
      parent = Event.find_by id: parent_id
      parent.attendees.each do |attendee|
        argv = {
          user_id: attendee.user_id,
          event_title: title,
          event_start_date: start_date,
          event_finish_date: finish_date,
          event_exception_type: exception_type
        }
        EmailWorker.perform_async argv, :delete_event
      end
    end
  end

  def send_email_delete_no_repeat_event
    attendees.each do |attendee|
      argv = {
        user_id: attendee.user_id,
        event_title: title,
        event_start_date: start_date,
        event_finish_date: finish_date,
        event_exception_type: nil
      }
      EmailWorker.perform_async argv, :delete_event
    end
  end
end
