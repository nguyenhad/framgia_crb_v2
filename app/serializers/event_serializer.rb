class EventSerializer < ActiveModel::Serializer
  attributes :id, :title, :description, :status, :color, :all_day,
    :repeat_type, :repeat_every, :user_id, :calendar_id, :start_date,
    :finish_date,:start_repeat, :end_repeat, :exception_time, :exception_type,
    :old_exception_type, :parent_id, :name_place, :place_id, :chatwork_room_id,
    :task_content, :message_content, :google_event_id, :google_calendar_id,
    :created_at, :updated_at, :deleted_at

  has_many :attendees
  has_many :users, through: :attendees
  has_many :repeat_ons
  has_many :days_of_weeks, through: :repeat_ons
  has_many :event_exceptions, class_name: Event.name, foreign_key: :parent_id
  has_many :notification_events
  has_many :notifications, through: :notification_events

  belongs_to :calendar
  belongs_to :owner, class_name: User.name, foreign_key: :user_id
  belongs_to :event_parent, class_name: Event.name, foreign_key: :parent_id
  belongs_to :place
end
