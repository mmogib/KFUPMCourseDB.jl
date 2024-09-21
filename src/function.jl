"""
    readdata(filepath::String, args...; kwargs...)::FileData

Reads data from a file and returns a `FileData` object, which includes the file path, a dictionary of field types, and the data as a `DataFrame`. 

# Arguments
- `filepath::String`: The path to the file to be read. Supported file formats are `.csv`, `.txt`, and `.xlsx`.
- `args...`: Positional arguments passed to the file reading functions (`XLSX.readtable` for `.xlsx` files).
- `kwargs...`: Keyword arguments passed to the file reading functions (`CSV.File` for `.csv` and `.txt` files, `XLSX.readtable` for `.xlsx`).

# Returns
- A `FileData` object containing:
    - `filepath`: The path of the file.
    - `fields`: A dictionary where the keys are the column names and the values indicate the data type (`"number"` for numeric fields and `"string"` for other types).
    - `data`: The content of the file as a `DataFrame`.

# Errors
- Throws an `AssertionError` if the file does not exist or if the file extension is not supported (`csv`, `txt`, `xlsx`).

# Example
```julia
file_data = readdata("data.csv", delim=',', header=true)
println(file_data.fields)  # Dict with column names and their types
println(file_data.data)    # DataFrame with the file content
"""
function readdata(filepath::String, args...; kwargs...)::FileData
    @assert isfile(filepath) "The file $filepath does not exist."
    kind = basename(filepath) |> d -> split(d, ".") |> d -> d[end]
    @assert kind in ["csv", "txt", "xlsx"] "The file extension $kind is not supported."
    data = if kind in ["csv", "txt"]
        CSV.File(filepath; kwargs...) |> DataFrame
    else
        XLSX.readtable(filepath, args...; kwargs...) |> DataFrame
    end

    fields = map(names(data)) do x
        val = typeof(x) <: Real ? "number" : "string"
        x => val
    end |> Dict

    FileData(filepath, fields, data)
end

"""
    createCourse(term::Union{Integer, String}, code::String, name::String, section::Union{Integer, String})::Course

Creates a `Course` object and populates it with students by fetching data from a database.

# Arguments
- `term::Union{Integer, String}`: The term in which the course is offered. This can be an integer (e.g., `241`) or a string (e.g., `"241"`).
- `code::String`: The course code (e.g., `"MATH 371"`).
- `name::String`: The name of the course (e.g., `"Introduction to Numerical Computing"`).
- `section::Union{Integer, String}`: The section number of the course, either as an integer or string.

# Returns
- A `Course` object that contains:
    - `course_with_id`: The course details (term, code, name, section) with an assigned unique ID from the database.
    - `students`: A list or collection of students enrolled in the course, fetched from the database.

# Example
```julia
course = createCourse("241", "MATH 371", "Introduction to Numerical Computing", 1)
println(course.students)  # Prints the list of students enrolled
"""
function createCourse(term::Union{Integer,String}, code::String, name::String, section::Union{Integer,String})
    course = Course(term, code, name, section)
    course_with_id = db_course(course)
    students = get_course_students(course_with_id.id)
    Course(course_with_id, students)
end
"""
    addStudents(c::Course, file_path::String, args...; fields::Union{Dict{Symbol, String}, Dict{Symbol, Any}}=Dict(:id => "id", :name => "name", :email => "email"), kwargs...)

Adds students to a `Course` object by reading data from a file and creating `Student` objects based on the file content.

# Arguments
- `c::Course`: The `Course` object to which students will be added.
- `file_path::String`: The path to the file containing student data. Supported file types are `csv`, `txt`, and `xlsx`.
- `args...`: Additional positional arguments passed to the file reading function (`readdata`).
- `fields::Union{Dict{Symbol, String}, Dict{Symbol, Any}}`: A dictionary mapping the student data fields (ID, name, and email) to their corresponding column names in the file. By default, it assumes `:id => "id"`, `:name => "name"`, and `:email => "email"`. If any field is a tuple, the first value is the column name, and the second value is a transformation function.
- `kwargs...`: Additional keyword arguments passed to the file reading function.

# Returns
- A new `Course` object containing the students loaded from the file, with student data saved to the database.

# Workflow
1. Reads the student data from the specified file using the `readdata` function.
2. Extracts student IDs, names, and emails based on the provided or default `fields` mapping.
3. Converts the extracted data to create `Student` objects.
4. Associates the students with the provided course and saves the student data to the database.

# Example
```julia
course = Course("241", "MATH 371", "Introduction to Numerical Computing", 1)
updated_course = addStudents(course, "students.csv", delim=',', header=true)
println(updated_course.students)  # Prints the list of added students
"""
function addStudents(c::Course, file_path::String, args...; fields::Union{Dict{Symbol,String},Dict{Symbol,Any}}=Dict(:id => "id", :name => "name", :email => "email"), kwargs...)
    dfile = readdata(file_path, args...; kwargs...)
    df = dfile.data |> dropmissing
    ids = if isa(fields[:id], Tuple)
        tids = map(x -> isa(x, Int) ? x : parse(Int, x), df[!, fields[:id][1]])
        map(fields[:id][2], tids)
    else
        map(x -> isa(x, Int) ? x : parse(Int, x), df[!, fields[:id]])
    end
    names = if isa(fields[:name], Tuple)
        fields[:name][2].(df[!, fields[:name][1]])
    else
        df[!, fields[:name]]
    end
    emails = if isa(fields[:email], Tuple)
        fields[:email][2].(df[!, fields[:email][1]])
    else
        df[!, fields[:email]]
    end
    course_with_id = db_course(c)
    students = map(i -> Student(ids[i], names[i], emails[i]), 1:length(ids))
    course = Course(course_with_id, students)
    course_students = save_students(course)

    Course(course, course_students)
end

"""
    ids(c::Course)::Vector{Int}

Retrieves the IDs of students enrolled in a given `Course`.

# Arguments
- `c::Course`: A `Course` object containing student data.

# Returns
- A `Vector{Int}` of student IDs. If the course has no students, returns an empty array.

# Example
```julia
course = createCourse(241, "MATH 371", "Introduction to Numerical Computing", 1)
student_ids = ids(course)
println(student_ids)  # Prints a vector of student IDs
"""

function ids(c::Course)
    students = c.students
    if length(students) > 0
        map(x -> x.id, students)
    else
        []
    end
end

"""
    names(c::Course)::Vector{String}

Retrieves the names of students enrolled in a given `Course`.

# Arguments
- `c::Course`: A `Course` object containing student data.

# Returns
- A `Vector{String}` of student names. If the course has no students, returns an empty array.

# Example
```julia
course = createCourse(241, "MATH 371", "Introduction to Numerical Computing", 1)
student_names = names(course)
println(student_names)  # Prints a vector of student names
"""
function names(c::Course)
    students = c.students
    if length(students) > 0
        map(x -> x.name, students)
    else
        []
    end
end

"""
    emails(c::Course)::Vector{String}

Retrieves the email addresses of students enrolled in a given `Course`.

# Arguments
- `c::Course`: A `Course` object containing student data.

# Returns
- A `Vector{String}` of student email addresses. If the course has no students, returns an empty array.

# Example
```julia
course = createCourse(241, "MATH 371", "Introduction to Numerical Computing", 1)
student_emails = emails(course)
println(student_emails)  # Prints a vector of student email addresses
"""
function emails(c::Course)
    students = c.students
    if length(students) > 0
        map(x -> x.email, students)
    else
        []
    end
end

"""
    addGrades(c::Course, file_path::String, args...;
        fields::Union{Dict{Symbol, String}, Dict{Symbol, Any}}=Dict(:sid => "sid", :name => "name", :value => "value", :max_value => "max_value"), kwargs...)

Adds student grades to a `Course` object by reading grade data from a file and creating `Grade` objects.

# Arguments
- `c::Course`: The `Course` object to which grades will be added.
- `file_path::String`: The path to the file containing grade data. Supported file types are `csv`, `txt`, and `xlsx`.
- `args...`: Additional positional arguments passed to the file reading function (`readdata`).
- `fields::Union{Dict{Symbol, String}, Dict{Symbol, Any}}`: A dictionary mapping the grade data fields (student ID, name, value, max value) to their corresponding column names in the file. Default mapping is `:sid => "sid"`, `:name => "name"`, `:value => "value"`, and `:max_value => "max_value"`. Each field can also be a tuple where the first value is the column name, and the second value is a transformation function.
- `kwargs...`: Additional keyword arguments passed to the file reading function.

# Returns
- A `Course` object with the added grades.

# Workflow
1. Reads the grade data from the specified file using `readdata`.
2. Extracts student IDs, names, grade values, and maximum possible values based on the provided or default `fields` mapping.
3. Creates `Grade` objects for each student in the course.
4. Filters out any grades that do not match the existing student IDs in the course.
5. Adds the valid grades to the course using the `add_student_grades` function.
6. If some grades cannot be matched to students, a warning is issued.

# Example
```julia
course = createCourse(241, "MATH 371", "Introduction to Numerical Computing", 1)
updated_course = addGrades(course, "grades.csv", delim=',', header=true)
println(updated_course.students)  # Prints the course with students and their grades
"""
function addGrades(c::Course, file_path::String, args...;
    fields::Union{Dict{Symbol,String},Dict{Symbol,Any}}=Dict(:sid => "sid", :name => "name", :value => "value", :max_value => "max_value"), kwargs...)
    dfile = readdata(file_path, args...; kwargs...)
    df = dfile.data |> dropmissing
    gids = if isa(fields[:sid], Tuple)
        tids = map(x -> isa(x, Int) ? x : parse(Int, x), df[!, fields[:sid][1]])
        map(fields[:sid][2], tids)
    else
        map(x -> isa(x, Int) ? x : parse(Int, x), df[!, fields[:sid]])
    end
    names = if isa(fields[:name], Tuple)
        fields[:name][2].(df[!, fields[:name][1]])
    else
        df[!, fields[:name]]
    end
    values = if isa(fields[:value], Tuple)
        fields[:value][2].(df[!, fields[:value][1]])
    else
        df[!, fields[:value]]
    end
    max_values = if isa(fields[:max_value], Tuple)
        fields[:max_value][2].(df[!, fields[:max_value][1]])
    else
        df[!, fields[:max_value]]
    end

    course_with_id = db_course(c)
    students = get_course_students(course_with_id.id)
    course = Course(course_with_id, students)
    students_ids = ids(course)
    grades = map(i -> Grade(gids[i], course_with_id.id, names[i], values[i], max_values[i]), 1:length(gids))
    filtered_grades = filter(x -> x.student_id in students_ids, grades)
    if length(grades) > length(filtered_grades)
        @warn "Some grades cannot be saved. No corresponding students. Maybe you need to add the missing students first."
    end
    add_student_grades(grades)

    Course(course, students)
end

"""
    getGrades(c::Course)::Union{Nothing, Vector{Grade}}

Retrieves the grades of students enrolled in a given `Course`.

# Arguments
- `c::Course`: A `Course` object for which to retrieve the grades.

# Returns
- A `Vector{Grade}` containing the grades of the students if the course has an existing ID.
- If the course is marked as "new" (i.e., `c.id == "new"`), returns `nothing` because no grades are associated with a new course.

# Example
```julia
course = createCourse(241, "MATH 371", "Introduction to Numerical Computing", 1)
grades = getGrades(course)
if grades !== nothing
    println(grades)  # Prints the grades of the students
else
    println("No grades available for a new course.")
end
"""
function getGrades(c::Course)
    if c.id == "new"
        nothing
    else
        get_course_grades(c)
    end
end


export readdata, createCourse, addStudents, ids, names, emails, addGrades, getGrades