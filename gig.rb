require "sinatra"
require "sinatra/reloader"
require "tilt/erubis"
require "yaml"
require "date"

configure do
  enable :sessions
  set :session_secret, 'secret'
end

before do
  session[:gigs] ||= []
  session[:past_gigs] ||=[]
  session[:temp] ||= []
end

helpers do
  def pack_date_time(year, date, time, pm)
    month, day = date.split('-')
    month.prepend('0') if month.size == 1
    day.prepend('0') if day.size == 1
    date = month + '-' + day
    ["#{year}-#{date}", convert_to_military_time(time, pm)]
  end

  def unpack_date_time(full_date, military_time)
    year, month, day = full_date.split("-")
    month.slice!(0) if month[0] == '0'
    day.slice!(0) if day[0] == '0'
    month_day = month + "-" + day
    time, pm = convert_to_regular_time(military_time)
    [year, month_day, time, pm]
  end
end

def all_gigs
  (session[:gigs] + session[:past_gigs]).flatten
end

def current_date_time
  date, time = Time.now.to_s.split(" ")[0, 2]
  time = time.split(":")[0, 2].join(":")
  [date, time]
end

def unpack_current_date_time
  date, time = current_date_time
  unpack_date_time(date, time)
end

def convert_to_regular_time(military_time)
  pm = 'am'
  hours, minutes = military_time.split(":")
  hours = hours.to_i
  if hours > 12
    hours -= 12
    pm = 'pm'
  elsif hours == 0
    hours = 12
  end
  ["#{hours}:#{minutes}", pm]
end

def convert_to_military_time(regular_time, pm)
  (regular_time += ':00') if (1..12).cover?(regular_time.to_i)
  hours, minutes = regular_time.split(':')
  hours = (pm == 'pm') ? (hours.to_i + 12).to_s : hours
  "#{hours}:#{minutes}"
end

def retrieve_current_gig
  date, time = params[:date_time].split("&")
  session[:gigs].each do |gig|
    return gig if gig[:date] == date && gig[:time] == time
  end
end

def today
  today, _ = current_date_time
  date_to_int(today)
end

def gig_id(gig)
  date = gig[:date].delete('-')
  time = gig[:time].delete(':')
  time = time.prepend '0' if time.size == 3
  (date + time).to_i
end

def sort_gigs
  session[:gigs].sort_by! do |gig|
    gig_id(gig)
  end
  organize_gigs
end

def organize_gigs
  while !session[:gigs].empty? && date_to_int(session[:gigs][0][:date]) < today
    session[:past_gigs] << session[:gigs].delete_at(0)
  end
end

def date_to_int(date)
  date.delete('-').to_i
end

def check_for_valid_time
  return "You must select either a.m. or p.m." if params[:pm].nil?
  time = params[:time]
  hours, minutes = time.split(':')
  return nil if minutes.nil? && (1..12).cover?(hours.to_i)
  "You must enter a valid time" if time.count(':') != 1 ||
                                    !time.scan(/[^\d:]/).empty? ||
                                    !(1..12).cover?(hours.to_i) ||
                                    !(0..59).cover?(minutes.to_i)    
end

def check_for_valid_date
  year = params[:year]
  month, day = params[:date].split('-')
  "Please select a year." if year.nil?
  "You must use (M)M-(D)D format." if params[:date].count('-') != 1
  "You must enter a valid date." if 
    !Date.valid_date?(year.to_i, month.to_i, day.to_i)
end

def check_for_valid_input
  return check_for_valid_time if check_for_valid_time
  return check_for_valid_date if check_for_valid_date
end

def four_years
  this_year = Time.now.year
  last_year, next_year, next_next_year = this_year - 1, this_year + 1, this_year + 2
  [last_year, this_year, next_year, next_next_year]
end

def total_income(gig_list)
  total = 0
  gig_list.each { |gig| total += gig[:income].to_f }
  total
end

def past_future_income
  [total_income(session[:past_gigs]), total_income(session[:gigs])]
end

def double_book(new_gig)
  'You already have a gig at this time!' if all_gigs.any? do
    |gig| gig_id(gig) == gig_id(new_gig)
  end
end

# View All Future Gigs
get "/" do
  sort_gigs
  @years = []
  @gig_list = session[:gigs]
  @last_year, @this_year, @next_year, @next_next_year = four_years
  @past_income, @future_income = past_future_income
  erb :all_gigs
end

get "/past_gigs" do
  @past_gigs = session[:past_gigs]
  @past_income, @future_income = past_future_income
  erb :past_gigs
end

get "/new_gig" do
  _, @date, @time, @pm = unpack_current_date_time
  _, @year, @year_1, @year_2 = four_years
  erb :new_gig
end

post "/new_gig" do
  session[:error] = check_for_valid_input
  redirect '/new_gig' if session[:error]

  date, time = pack_date_time(params[:year], params[:date], params[:time], params[:pm])

  new_gig = { name: params[:name], 
              date: date, 
              time: time,
              income: params[:income] }

  session[:error] = double_book(new_gig)
  redirect '/new_gig' if session[:error]

  session[:gigs] << new_gig
  session[:success] = "Gig created successfully!"
  redirect "/"
end

# Edit/View Gig
get "/:date_time" do
  current_gig = retrieve_current_gig
  _, @current_year, @current_year_1, @current_year_2 = four_years

  @year, @date, @time, @pm = unpack_date_time(current_gig[:date], current_gig[:time])
  @year = @year.to_i

  @income, @name = current_gig[:income], current_gig[:name]
  session[:temp] = current_gig
  erb :edit
end

post "/edit" do
  session[:error] = check_for_valid_input
  redirect '/' if session[:error]

  date, time = pack_date_time(params[:year], params[:date], params[:time], params[:pm])

  new_gig = { name: params[:name],
              date: date, 
              time: time,
              income: params[:income] }
  session[:success] = 'Gig was unchanged' if new_gig == session[:temp]
  redirect '/' if session[:success]

  session[:gigs].delete(session[:temp])
  session[:gigs] << new_gig
  session[:success] = "Gig edited successfully!"
  redirect "/"
end
