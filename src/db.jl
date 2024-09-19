### Course
function db_course(c::Course)
    db = getdb()
    DBInterface.execute(db, "insert or ignore into courses (term,code,name,section) values (?,?,?,?)", [c.term, c.code, c.name, c.section])
    df = DBInterface.execute(db, "select * from courses where term=? and code=? and name=? and section=?", [c.term, c.code, c.name, c.section]) |> DataFrame
    SQLite.close(db)
    CourseWithID(df[!, :id][1], c)
end



function save_students(students::Vector{Student}, course::CourseWithID)
    add_students(students)
    add_student_courses(students, course)
    get_course_students(course.id)
end

function reset_db()
    db = getdb(true)
    SQLite.close(db)
end

function get_student(id::Int)
    db = getdb()
    df = DBInterface.execute(db, "select * from students where id=?", [id]) |> DataFrame
    SQLite.close(db)
    df
end

function get_course_students(course_id::Int)
    db = getdb()
    sql = """
        select 
            t1.* 
        from 
            students t1
        inner join 
            student_courses t2 on t1.id=t2.student_id
        where 
            t2.course_id=?
    """
    df = DBInterface.execute(db, sql, [course_id]) |> DataFrame
    SQLite.close(db)
    map(x -> Student(x[:id], x[:name], x[:email]), eachrow(df))
end




function add_students(students::Vector{Student})
    db = getdb()
    values = join(map(x -> "($(x.id),'$(x.name)','$(x.email)')", students), ",")
    DBInterface.execute(db, "insert or ignore into students (id,name,email) values $values")
    SQLite.close(db)
    students
end

function add_student_courses(students::Vector{Student}, c::CourseWithID)
    values = join(map(x -> "($(x.id),$(c.id))", students), ",")
    db = getdb()
    sql = "insert or ignore into student_courses (student_id,course_id) values $values;"
    DBInterface.execute(db, sql)
    SQLite.close(db)
    students
end

function add_student_grades(student_grades::Vector{Grade})
    values = join(map(x -> "($(x.student_id),$(x.course_id),'$(x.name)',$(x.value),$(x.max_value))", student_grades), ",")
    db = getdb()
    sql = "insert or ignore into student_grades (student_id,course_id,grade_name,grade_value,grade_max) values $values;"
    println(sql)
    DBInterface.execute(db, sql)
    SQLite.close(db)
end

function add_course(course::String, term::String, section::String)
    db = getdb()
    DBInterface.execute(db, "insert or ignore into courses (course,term,section) values (?,?,?)", [course, term, section])
    sql_statemnt = "select * from courses where term='$term' and course='$course' and section='$section';"
    df = DBInterface.execute(db, sql_statemnt) |> DataFrame
    SQLite.close(db)
    df
end
# function load_students()
#     db = getdb()
#     df = DBInterface.execute(db, "select * from students;") |> DataFrame
#     SQLite.close(db)
#     df
# end

# function load_students(file_name::String; new_course::Bool=false)
#     new_course == true && @assert isfile(file_name) "The file name provided $file_name doe not exist."
#     db = getdb()
#     df0 = DBInterface.execute(db, "select * from students;") |> DataFrame
#     df = if nrow(df0) > 0
#         load_students(df)
#         df
#     else
#     end
#     SQLite.close(db)
#     df
# end

function savescores(grade_name::String, filename::String)
    df = get_scores(grade_name)
    savecsv(df, filename)
    df
end


function get_scores(grade_name)
    db = getdb()
    df = DBInterface.execute(
        db,
        """
    select 
        t1.*,t2.*,t3.* 
    from 
        student_grades t1 
    inner join 
        students t2 on t1.student_id=t2.id 
    inner join 
        courses t3 on t1.course_id = t3.id
    where 
        grade_name='$grade_name' 
    order by t3.section, t2.id;
"""
    ) |> DataFrame
    SQLite.close(db)
    df
end

function getdb(reset_db=false)
    dbpath = "database/courses.db"
    mkpath(dirname(dbpath))
    db = SQLite.DB(dbpath)
    if reset_db
        foreach(["student_courses", "student_grades", "students", "courses"]) do table
            DBInterface.execute(db, "DROP TABLE IF EXISTS $table;")
        end
    end

    # SQL statement to create the students table (if not already created)
    create_students_table_sql = """
    CREATE TABLE IF NOT EXISTS students (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT NOT NULL
    );
    """
    # Execute the SQL statement
    DBInterface.execute(db, create_students_table_sql)
    creat_courses_table_sql = """
     CREATE TABLE IF NOT EXISTS courses (
         id INTEGER PRIMARY KEY AUTOINCREMENT,
         term TEXT NOT NULL,
         code TEXT NOT NULL,
         name TEXT NOT NULL,
         section TEXT NOT NULL,
         UNIQUE(term, code, section)
     );
     """
    DBInterface.execute(db, creat_courses_table_sql)
    creat_reg_table_sql = """
     CREATE TABLE IF NOT EXISTS student_courses (
         student_id INTEGER NOT NULL,
         course_id INTEGER NOT NULL,
         UNIQUE(student_id,course_id)
     );
     """
    DBInterface.execute(db, creat_reg_table_sql)
    create_scores_table_sql = """
    CREATE TABLE IF NOT EXISTS student_grades (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER,
        course_id INTEGER,
        grade_name TEXT,
        grade_value REAL,
        grade_max REAL,
        UNIQUE(student_id,course_id,grade_name)
    );
    """
    # Execute the SQL statement
    DBInterface.execute(db, create_scores_table_sql)
    db
end

function savecsv(df::DataFrame, filename::String; args...)
    folder = dirname(filename)
    file_base = basename(filename)
    file_path = mkpath(folder)
    CSV.write("$file_path/$file_base", eachrow(df); args...)
end


export reset_db