mysql_online_alter_table
========================

Script to generate scripts to allow online modification of a MySQL table

Altering large MySQL tables is a pain.  Almost every ALTER TABLE command results in MySQL doing the following:
* Creation of a temporary copy of the table
* Doing the modification on the temporary copy
* Dropping the original table
* Renaming the copy to the original

The whole time the above happens, the table is locked.  If you do that to a table with millions of rows, it will take minutes, even hours.

This script generates code that will allow you to do the modification in steps without locking the original table, enabling an online alteration without having to schedule a maintenance downtime.  This involves: 
* Creating a temporary copy of the table
* Creating triggers so that changes on the original table will be reflected to the temporary copy
* Copying data from the original table in batches
* Renaming the tables

Usage:
- Modify alter_table.rb to put database connection parameters
- Run: ruby alter_table.rb table_name 'modifications' e.g. ruby alter_table.rb my_table 'add new_column integer, add index (column_name)'
- Take a look at the generated files and follow instructions

TODO/Known Issues:
* Current version does not handle foreign key constraints that reference the table to be modified.  At the end they will still reference the old table.  For now consider disabling foreign key checks then drop the original table before renaming the new table.

Standard Disclaimer: Use at your own risk, I will not be responsible for whatever happens to your database.

Note that there is also Online Schema Change tool from Percona Toolkit (http://www.percona.com/doc/percona-toolkit/2.1/pt-online-schema-change.html), which I discovered after creating this script.  I think the advantage of having this script is you can do the actual table cutover on your own time.
