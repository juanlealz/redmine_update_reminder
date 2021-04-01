namespace :redmine_update_reminder do
  require 'redmine/utils'
  include Redmine::Utils::DateCalculation

  def send_user_issue_estimates_reminders(issue_status_ids, user, mailed_issue_ids)
    issues_with_updated_since = []
    trackers = Tracker.all
    trackers.each do |tracker|
      issue_status_ids.each do |issue_status_id|
        estimate_update = Setting.plugin_redmine_update_reminder["#{tracker.id}-status-#{issue_status_id}-estimate"].to_f      

        if estimate_update > 0
          oldest_estimated_since = estimate_update.days.ago

          issues = Issue.where(tracker_id: tracker.id, assigned_to_id: user.id, status_id: issue_status_id).
            where('estimated_hours IS NULL OR estimated_hours <= 0').
            where.not(id: mailed_issue_ids.to_a)

          issues.each do |issue|
            if issue.updated_on < oldest_estimated_since
              issues_with_updated_since << [issue, issue.updated_on]
            end
          end
        end
      end
    end
    RemindingMailer.remind_user_issue_estimates(user, 
      issues_with_updated_since).deliver_now if issues_with_updated_since.count > 0
  end
  
  def send_user_past_due_issues_reminders(issue_status_ids, user, mailed_issue_ids)
    issues = Issue.where(assigned_to_id: user.id, 
      status_id: issue_status_ids).where('due_date < ?', Date.today).
      where.not(id: mailed_issue_ids.to_a)
    
    RemindingMailer.remind_user_past_due_issues(user, issues).deliver_now if issues.exists?
  end
  def send_user_tracker_reminders(issue_status_ids, user, mailed_issue_ids)
    trackers = Tracker.all
    issues_with_updated_since = []
    trackers.each do |tracker|
      update_duration = Setting.plugin_redmine_update_reminder["#{tracker.id}_update_duration"].to_f
      if update_duration > 0

        updated_since = update_duration.days.ago
        issues = Issue.where(tracker_id: tracker.id, assigned_to_id: user.id, status_id: issue_status_ids).
          where('updated_on < ?', updated_since).where.not(id: mailed_issue_ids.to_a)

        issues.find_each do |issue|
          issues_with_updated_since << [issue, issue.updated_on]
        end
      end      
    end    
    RemindingMailer.remind_user_issue_trackers(user, 
      issues_with_updated_since).deliver_now if issues_with_updated_since.count > 0
  end
  
  def send_user_status_reminders(issue_status_ids, user, mailed_issue_ids)
    issues_with_updated_since = []
    trackers = Tracker.all
    trackers.each do |tracker|
      issue_status_ids.each do |issue_status_id|
        update_duration = Setting.plugin_redmine_update_reminder["#{tracker.id}-status-#{issue_status_id}-update"].to_f      
        if update_duration > 0

          oldest_status_date = update_duration.days.ago
          issues = Issue.where(tracker_id: tracker.id, assigned_to_id: user.id, status_id: issue_status_id).
            where.not(id: mailed_issue_ids.to_a)

          issues.find_each do |issue|       
            issue.journals.each do |journal|
              journal.visible_details do |detail|
                if detail[:prop_key] == 'status_id' && 
                    detail[:new_value] == issue_status_id && 
                    oldest_status_date > journal.created_on
                  issues_with_updated_since << [issue, journal.created_on]
                  break                  
                end
              end
            end
          end
        end      
      end    
    end
    RemindingMailer.remind_user_issue_statuses(user, 
      issues_with_updated_since).deliver_now if issues_with_updated_since.count > 0    
  end  
  
  def send_issue_status_reminders(issue_status_ids, user_ids, mailed_issue_ids)
    Tracker.all.each do |tracker|
      issue_status_ids.each do |issue_status_id|
        update_duration = Setting.plugin_redmine_update_reminder["#{tracker.id}-status-#{issue_status_id}-update"].to_f      
        if update_duration > 0
          #puts "He encontrado una notificación que tengo que enviar para el tracker #{tracker}"

          oldest_status_date = update_duration.days.ago
          puts "issue_status_id = #{issue_status_id} oldest_status_date = #{oldest_status_date}"
          issues = Issue.where(tracker_id: tracker.id, assigned_to_id: user_ids, 
            status_id: issue_status_id).where.not(id: mailed_issue_ids.to_a)

          issues.find_each do |issue|       
            puts "He encontrado una ficha que tengo que analizar: #{issue}"
            issue.journals.each do |journal|
              #puts "He encontrado un journal que tengo que analizar: #{journal} con los detalles #{journal.visible_details}"
              journal.visible_details.each do |detail|
                if detail[:prop_key] == 'status_id'
                  puts "   Analizando detalle #{detail.id}: prop_key #{detail[:prop_key]}, new_value #{detail[:value]}, created_on #{journal.created_on}"
                end
                if detail[:prop_key] == 'status_id' && 
                    detail[:value].to_i == issue_status_id && 
                    oldest_status_date > journal.created_on
                  puts "-----------Enviando email a #{issue.assigned_to}"
                  RemindingMailer.reminder_status_email(issue.assigned_to, issue, 
                    journal.created_on).deliver_now
                  mailed_issue_ids << issue.id
                  break
                end
              end
            end
          end
        end      
      end    
    end
  end
  
  def send_issue_tracker_reminders(issue_status_ids, user_ids, mailed_issue_ids)
    trackers = Tracker.all
    
    trackers.each do |tracker|
      update_duration = Setting.plugin_redmine_update_reminder["#{tracker.id}_update_duration"].to_f
      if update_duration > 0
        
        updated_since = update_duration.days.ago
      	issues = Issue.where(tracker_id: tracker.id, assigned_to_id: user_ids, 
          status_id: issue_status_ids).where('updated_on < ?', updated_since).
          where.not(id: mailed_issue_ids.to_a)

        issues.find_each do |issue|       
          RemindingMailer.reminder_issue_email(issue.assigned_to, issue, issue.updated_on).deliver_now
          mailed_issue_ids << issue.id
        end
      end      
    end
    
  end

  def send_last_login_reminders(users)
      max_inactivity = Setting.plugin_redmine_update_reminder["remind_days_since_last_login"].to_f
      if max_inactivity > 0
        users.delete_if do |user|
          last_login = user.last_login_on
          if !last_login.nil? and (last_login < DateTime.now - max_inactivity.days)
            RemindingMailer.reminder_inactivity_login(user, last_login).deliver_now
            true
          else
            false
          end
        end
      end
  end

  def send_last_note_reminders(users)
      max_inactivity = Setting.plugin_redmine_update_reminder["remind_days_since_last_note"].to_f
      if max_inactivity > 0
        users.find_all do |user|
          last_note = Journal.where(user_id: user.id).maximum(:created_on)
          if !last_note.nil? and (last_note < DateTime.now - max_inactivity.days)
            RemindingMailer.reminder_inactivity_notes(user, last_note).deliver_now
          end
        end
      end
  end

  def users_to_remind
    remind_group = Setting.plugin_redmine_update_reminder['remind_group']        
    if remind_group == "all"
      User.all
    else
      Group.includes(:users).find(remind_group).users
    end
  end

  def prepare_locale
     include ActionView::Helpers::DateHelper
    ::I18n.locale = Setting.default_language
  end

  def inactivity_reminders
    prepare_locale
    if Setting.plugin_redmine_update_reminder['inactivity_enabled']
      puts "Sending inactivity reminders"
      users = users_to_remind.to_a
      send_last_login_reminders(users)
      send_last_note_reminders(users)
    end
  end
 
  def user_reminders
    prepare_locale
    if Setting.plugin_redmine_update_reminder['user_updates_enabled']
      puts "Sending user reminders"
      open_issue_status_ids = IssueStatus.where(is_closed: false).pluck('id')
      remind_group = Setting.plugin_redmine_update_reminder['remind_group']        
      if remind_group == "all"
        users = User.all
      else
        users = Group.includes(:users).find(remind_group).users
      end

      users_to_remind.find_each do |user|
        mailed_issue_ids = Set.new
        send_user_tracker_reminders(open_issue_status_ids, user, mailed_issue_ids)
        send_user_status_reminders(open_issue_status_ids, user, mailed_issue_ids)
        send_user_past_due_issues_reminders(open_issue_status_ids, user, mailed_issue_ids)
        send_user_issue_estimates_reminders(open_issue_status_ids, user, mailed_issue_ids)
      end
    end
  end

  def issue_reminders
    prepare_locale
    if Setting.plugin_redmine_update_reminder['issue_updates_enabled']
      puts "Sending issue reminders"
      open_issue_status_ids = IssueStatus.where(is_closed: false).pluck('id')

      remind_group = Setting.plugin_redmine_update_reminder['remind_group']        
      if remind_group == "all"
        user_ids = User.all.ids
      else
        user_ids = Group.includes(:users).find(remind_group).user_ids
      end


      mailed_issue_ids = Set.new

      send_issue_tracker_reminders(open_issue_status_ids, user_ids, mailed_issue_ids)
      send_issue_status_reminders(open_issue_status_ids, user_ids, mailed_issue_ids)
    end
  end

  task send_inactivity_reminders: :environment do
    inactivity_reminders
  end

  task send_user_reminders: :environment do
    user_reminders
  end
  
  task send_issue_reminders: :environment do    
    issue_reminders
  end

  task send_all_reminders: :environment do
    inactivity_reminders
    user_reminders
    issue_reminders
  end
end
