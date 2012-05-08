require 'rubygems'
require 'sequel'

############################# CONFIGURE THE FOLLOWING ########################
DBHOST = ""
DBSCHEMA = ""
DBUSER = ""
DBPASS = ""
BATCH_SIZE = 1000
############################# END USER CONFIGURABLE PART ######################

DB = Sequel.connect(:adapter => "mysql",
                    :host => DBHOST,
                    :database => DBSCHEMA,
                    :user => DBUSER,
                    :password => DBPASS )

if ARGV.length != 2
  puts "Usage: ruby alter_table.rb <table_name> '<modifications>'"
  puts "e.g. ruby alter_table.rb my_table 'add new_column integer, add index (column_name)'"
  exit 1
end
table_name = ARGV[0]
table_name_new = table_name + "_new"
modifications = ARGV[1]
primary_key_column = ""

if DB.fetch("select table_name from information_schema.tables where table_name='#{table_name}' and table_schema='#{DBSCHEMA}'").first.nil?
  puts "No #{table_name} table found in #{DBSCHEMA} database"
else
  puts "#{DBSCHEMA}.#{table_name} found. Proceeding"
  column_array = []
  DB.fetch("select column_name, column_key from information_schema.columns where table_name='#{table_name}' and table_schema='#{DBSCHEMA}' order by ordinal_position") do |row|
    column_array << "`#{row[:column_name]}`"
    if row[:column_key] == "PRI"
      primary_key_column = "`#{row[:column_name]}`"
    end
  end
  column_list = column_array.join(",")
  column_list_for_print = column_array.join("\n")
end

sql_file_name = "modify-#{table_name}.sql"
ruby_file_name = "copy-#{table_name}.rb"
#puts sql_file_name

sql_file_contents = <<eos
/* SANITY CHECK: listing existing table columns (you can compare with output of 'desc #{table_name}'):
#{column_list_for_print}
*/
#RUN THE FOLLOWING FIRST:
create table #{table_name}_new like #{table_name};
alter table #{table_name}_new #{modifications};

delimiter |
create trigger #{table_name}_insert
after insert on #{table_name}
for each row begin
  insert into #{table_name_new}
    (#{column_list})
    select #{column_list}
    from #{table_name} where #{primary_key_column}=NEW.#{primary_key_column};
end;|
\
create trigger #{table_name}_update
after update on #{table_name}
for each row begin
  replace into #{table_name_new}
    (#{column_list})
    select #{column_list}
    from #{table_name} where #{primary_key_column}=NEW.#{primary_key_column};
end;|

create trigger #{table_name}_delete
after delete on #{table_name}
for each row begin
  delete from #{table_name_new}
  where #{primary_key_column}=OLD.#{primary_key_column};
end;|
delimiter ;

#After runnning the above you can run the #{ruby_file_name} script to copy contents of #{table_name} to #{table_name_new}

#THE SQL COMMANDS BELOW ARE COMMENTED OUT TO MAKE SURE THEY ARE NOT RUN ACCIDENTALLY

#During cutover, execute the following:
#rename table #{table_name} to #{table_name}_old, #{table_name_new} to #{table_name};

#When everything is okay, run the folllowing:
#drop table #{table_name}_old;
eos
f = File.new(sql_file_name,"w+")
f.puts sql_file_contents
f.close

ruby_file_contents = <<eos
require 'rubygems'
require 'sequel'

BATCH_SIZE = #{BATCH_SIZE}
DB = Sequel.connect(:adapter => 'mysql',:host => '#{DBHOST}', :database => '#{DBSCHEMA}', :user => '#{DBUSER}', :password => '#{DBPASS}' )
min_max = DB["select min(id) min_id, max(id) max_id from #{table_name}"]

start_id = min_max.map(:min_id)[0].to_i
end_id = start_id + BATCH_SIZE - 1
max_id = min_max.map(:max_id)[0].to_i

while start_id < max_id do
  puts "copying \#{start_id} to \#{end_id} of \#{max_id}"
  DB.execute("replace into #{table_name_new} (#{column_list}) select #{column_list} from #{table_name} where #{primary_key_column} between \#{start_id} and \#{end_id}")
  start_id = start_id + BATCH_SIZE
  end_id = end_id + BATCH_SIZE
end

eos
f = File.new(ruby_file_name,"w+")
f.puts ruby_file_contents
f.close

puts "Please see #{sql_file_name} and #{ruby_file_name}"
