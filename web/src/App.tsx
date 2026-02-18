import { useMemo, useState } from 'react';
import './styles.css';

type ParentLink = {
  id: string;
  parent_id: string;
  parent_name: string;
  parent_phone: string;
  student_id: string;
  student_name: string;
  class_label: string;
  roll_number: number;
  status: string;
  created_at: string;
};

type StudentRecord = {
  id: string;
  full_name: string;
  class_label: string;
  roll_number: number;
  date_of_birth: string;
  house: string;
  parent_phone: string;
  admission_year: number;
};

type EventRecord = {
  id: string;
  title: string;
  description: string;
  event_date: string;
  start_time: string;
  end_time: string;
  location: string;
  audience: string;
  category: string;
  published: boolean;
};

type DashboardWidgetRecord = {
  key: string;
  label: string;
  value: string;
  hint: string;
  icon: string;
};

type AppConfigRecord = {
  feature_flags: Record<string, boolean>;
  dashboard_widgets: DashboardWidgetRecord[];
};

const API_BASE_URL = 'https://jnv-web.onrender.com';

export default function App() {
  const [token, setToken] = useState('dev:+919999999999:admin');
  const [status, setStatus] = useState('');

  const [uploadClass, setUploadClass] = useState('Class 10');
  const [uploadExam, setUploadExam] = useState('Term 1 - Quarterly');
  const [uploadDate, setUploadDate] = useState('');
  const [uploadTerm, setUploadTerm] = useState('Term 1');
  const [uploadFile, setUploadFile] = useState<File | null>(null);

  const [manualClass, setManualClass] = useState('Class 10');
  const [manualSubject, setManualSubject] = useState('Mathematics');
  const [manualMaxMarks, setManualMaxMarks] = useState(100);
  const [manualExam, setManualExam] = useState('Term 1 - Quarterly');
  const [manualDate, setManualDate] = useState('');
  const [manualTerm, setManualTerm] = useState('Term 1');
  const [manualRows, setManualRows] = useState([
    { roll: '12', name: 'Aarav Sharma', score: '95', grade: 'A+' },
    { roll: '14', name: 'Riya Verma', score: '88', grade: 'A' },
  ]);

  const [annTitle, setAnnTitle] = useState('');
  const [annCategory, setAnnCategory] = useState('Academic');
  const [annPriority, setAnnPriority] = useState('High');
  const [annMessage, setAnnMessage] = useState('');
  const [announcements, setAnnouncements] = useState<Array<Record<string, unknown>>>([]);
  const [pendingLinks, setPendingLinks] = useState<ParentLink[]>([]);
  const [students, setStudents] = useState<StudentRecord[]>([]);
  const [studentFullName, setStudentFullName] = useState('');
  const [studentClass, setStudentClass] = useState('Class 10');
  const [studentRoll, setStudentRoll] = useState('');
  const [studentDob, setStudentDob] = useState('');
  const [studentHouse, setStudentHouse] = useState('Ashoka');
  const [studentParentPhone, setStudentParentPhone] = useState('');
  const [studentAdmissionYear, setStudentAdmissionYear] = useState(`${new Date().getFullYear()}`);
  const [events, setEvents] = useState<EventRecord[]>([]);
  const [eventTitle, setEventTitle] = useState('');
  const [eventDescription, setEventDescription] = useState('');
  const [eventDate, setEventDate] = useState('');
  const [eventStartTime, setEventStartTime] = useState('');
  const [eventEndTime, setEventEndTime] = useState('');
  const [eventLocation, setEventLocation] = useState('');
  const [eventAudience, setEventAudience] = useState('All Students');
  const [eventCategory, setEventCategory] = useState('Academic');
  const [featureFlags, setFeatureFlags] = useState<Record<string, boolean>>({
    show_events: true,
    show_announcements: true,
    show_attendance: false,
    show_academic_tab: true,
  });
  const [dashboardWidgets, setDashboardWidgets] = useState<DashboardWidgetRecord[]>([
    { key: 'gpa', label: 'GPA', value: '9.2', hint: 'This term', icon: 'school' },
    { key: 'attendance', label: 'Attend', value: '94.5%', hint: 'Monthly avg', icon: 'check_circle' },
    { key: 'rank', label: 'Rank', value: '#3', hint: 'Class standing', icon: 'emoji_events' },
  ]);

  const authHeader = useMemo(() => ({
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  }), [token]);

  const authOnlyHeader = useMemo(() => ({
    Authorization: `Bearer ${token}`,
  }), [token]);

  const postJSON = async (path: string, payload: unknown) => {
    const res = await fetch(`${API_BASE_URL}${path}`, {
      method: 'POST',
      headers: authHeader,
      body: JSON.stringify(payload),
    });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(body || res.statusText);
    }
    return res.json();
  };

  const getJSON = async (path: string) => {
    const res = await fetch(`${API_BASE_URL}${path}`, {
      headers: authHeader,
    });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(body || res.statusText);
    }
    return res.json();
  };

  const handlePublishAnnouncement = async () => {
    try {
      setStatus('Publishing announcement...');
      await postJSON('/api/v1/announcements', {
        title: annTitle,
        content: annMessage,
        category: annCategory,
        priority: annPriority.toLowerCase(),
      });
      setStatus('Announcement created (pending publish).');
      setAnnTitle('');
      setAnnCategory('Academic');
      setAnnPriority('High');
      setAnnMessage('');
      await loadAnnouncements();
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    }
  };

  const loadAnnouncements = async () => {
    try {
      setStatus('Loading announcements...');
      const items = await getJSON('/api/v1/announcements');
      setAnnouncements(items);
      setStatus('Announcements loaded.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    }
  };

  const loadPendingLinks = async () => {
    try {
      setStatus('Loading pending parent links...');
      const items = await getJSON('/api/v1/parent-links/pending');
      if (!Array.isArray(items)) {
        setPendingLinks([]);
        setStatus('No request data returned from server.');
        return;
      }
      setPendingLinks(items as ParentLink[]);
      setStatus('Pending links loaded.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
      setPendingLinks([]);
    }
  };

  const approveParentLink = async (id: string) => {
    try {
      setStatus('Approving parent link...');
      await postJSON(`/api/v1/parent-links/${id}/approve`, {});
      setPendingLinks((prev) => prev.filter((item) => item.id !== id));
      setStatus('Parent link approved.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    }
  };

  const publishAnnouncement = async (id: string) => {
    try {
      setStatus('Publishing announcement...');
      await postJSON(`/api/v1/announcements/${id}/publish`, {});
      await loadAnnouncements();
      setStatus('Announcement published.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    }
  };

  const loadEvents = async () => {
    try {
      setStatus('Loading events...');
      const items = await getJSON('/api/v1/events');
      setEvents(Array.isArray(items) ? (items as EventRecord[]) : []);
      setStatus('Events loaded.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
      setEvents([]);
    }
  };

  const createEvent = async () => {
    try {
      if (!eventTitle || !eventDate) {
        setStatus('Please enter event title and event date.');
        return;
      }
      setStatus('Creating event draft...');
      await postJSON('/api/v1/events', {
        title: eventTitle,
        description: eventDescription,
        event_date: eventDate,
        start_time: eventStartTime,
        end_time: eventEndTime,
        location: eventLocation,
        audience: eventAudience,
        category: eventCategory,
      });
      setEventTitle('');
      setEventDescription('');
      setEventDate('');
      setEventStartTime('');
      setEventEndTime('');
      setEventLocation('');
      setEventAudience('All Students');
      setEventCategory('Academic');
      await loadEvents();
      setStatus('Event created as draft.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    }
  };

  const publishEvent = async (id: string) => {
    try {
      setStatus('Publishing event...');
      await postJSON(`/api/v1/events/${id}/publish`, {});
      await loadEvents();
      setStatus('Event published.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    }
  };

  const loadAppConfig = async () => {
    try {
      setStatus('Loading app config...');
      const config = await getJSON('/api/v1/app-config') as AppConfigRecord;
      setFeatureFlags(config.feature_flags ?? {});
      setDashboardWidgets(Array.isArray(config.dashboard_widgets) ? config.dashboard_widgets : []);
      setStatus('App config loaded.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    }
  };

  const saveAppConfig = async () => {
    try {
      setStatus('Saving app config...');
      await postJSON('/api/v1/app-config', {
        feature_flags: featureFlags,
        dashboard_widgets: dashboardWidgets,
      });
      setStatus('App config saved.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    }
  };

  const setFlag = (key: string, value: boolean) => {
    setFeatureFlags((prev) => ({ ...prev, [key]: value }));
  };

  const updateWidget = (index: number, field: keyof DashboardWidgetRecord, value: string) => {
    setDashboardWidgets((prev) =>
      prev.map((item, i) => (i === index ? { ...item, [field]: value } : item))
    );
  };

  const loadStudents = async () => {
    try {
      setStatus('Loading students...');
      const items = await getJSON(`/api/v1/students?class=${encodeURIComponent(studentClass)}`);
      setStudents(items as StudentRecord[]);
      setStatus('Students loaded.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    }
  };

  const createStudent = async () => {
    try {
      if (!studentFullName || !studentClass || !studentRoll || !studentDob) {
        setStatus('Please fill required student fields.');
        return;
      }
      if (studentParentPhone) {
        const normalized = studentParentPhone.trim();
        const valid =
          /^[0-9]{10}$/.test(normalized) ||
          /^91[0-9]{10}$/.test(normalized) ||
          /^\+91[0-9]{10}$/.test(normalized);
        if (!valid) {
          setStatus('Parent phone must be 10 digits, 91XXXXXXXXXX, or +91XXXXXXXXXX.');
          return;
        }
      }
      setStatus('Creating student...');
      await postJSON('/api/v1/students', {
        full_name: studentFullName,
        class_label: studentClass,
        roll_number: Number(studentRoll),
        date_of_birth: studentDob,
        house: studentHouse,
        parent_phone: studentParentPhone,
        admission_year: Number(studentAdmissionYear || new Date().getFullYear()),
      });
      setStatus('Student created.');
      setStudentFullName('');
      setStudentRoll('');
      setStudentDob('');
      setStudentParentPhone('');
      await loadStudents();
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    }
  };

  const createExam = async (title: string, classLabel: string, term: string, date: string) => {
    const exam = await postJSON('/api/v1/exams', {
      title,
      class: classLabel,
      term,
      date,
    });
    return exam.id as string;
  };

  const lookupStudent = async (classLabel: string, roll: string) => {
    const params = new URLSearchParams({ class: classLabel, roll });
    return getJSON(`/api/v1/students/lookup?${params.toString()}`);
  };

  const submitScores = async (examId: string, scores: Array<Record<string, unknown>>) => {
    await postJSON(`/api/v1/exams/${examId}/scores`, { scores });
  };

  const handleManualSubmit = async () => {
    try {
      setStatus('Submitting manual scores...');
      if (!manualDate) {
        setStatus('Please select exam date for manual entry.');
        return;
      }
      const examId = await createExam(manualExam, manualClass, manualTerm, manualDate);
      const scores: Array<Record<string, unknown>> = [];
      for (const row of manualRows) {
        if (!row.roll || !row.score) continue;
        const student = await lookupStudent(manualClass, row.roll);
        scores.push({
          student_id: student.id,
          subject: manualSubject,
          score: Number(row.score),
          max_score: Number(manualMaxMarks),
          grade: row.grade || '',
        });
      }
      await submitScores(examId, scores);
      setStatus('Manual scores submitted for approval.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    }
  };

  const handleUploadScores = async () => {
    try {
      if (!uploadFile) {
        setStatus('Please select a CSV file.');
        return;
      }
      if (!uploadDate) {
        setStatus('Please select exam date for upload.');
        return;
      }
      setStatus('Uploading CSV to server...');
      const examId = await createExam(uploadExam, uploadClass, uploadTerm, uploadDate);
      const formData = new FormData();
      formData.append('file', uploadFile);
      const res = await fetch(`${API_BASE_URL}/api/v1/exams/${examId}/scores/upload`, {
        method: 'POST',
        headers: authOnlyHeader,
        body: formData,
      });
      const body = await res.json();
      if (!res.ok) {
        const errors = Array.isArray(body.errors) ? body.errors.join(', ') : res.statusText;
        throw new Error(errors);
      }
      setStatus(`Uploaded ${body.inserted} scores for approval.`);
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    }
  };

  const updateManualRow = (index: number, field: string, value: string) => {
    setManualRows((prev) =>
      prev.map((row, i) => (i === index ? { ...row, [field]: value } : row))
    );
  };

  return (
    <div className="app">
      <header className="app__header">
        <div className="app__brand">
          <span className="app__logo" />
          <div>
            <h1>JNV Admin Portal</h1>
            <p>Scores, announcements, and approvals</p>
          </div>
        </div>
        <div className="header-actions">
          <span className="api-badge">API: {API_BASE_URL}</span>
          <input
            className="token-input"
            value={token}
            onChange={(event) => setToken(event.target.value)}
            placeholder="Auth token"
          />
        </div>
      </header>

      <main className="app__content">
        <section className="card card--wide">
          <div className="card__header">
            <div>
              <h2>Student Master Data</h2>
              <p>Add student details first so parent linking and marks upload work correctly.</p>
            </div>
            <button className="app__button" onClick={loadStudents}>Refresh students</button>
          </div>
          <div className="form-grid">
            <label className="field">
              Student Name
              <input value={studentFullName} onChange={(event) => setStudentFullName(event.target.value)} />
            </label>
            <label className="field">
              Class
              <select value={studentClass} onChange={(event) => setStudentClass(event.target.value)}>
                <option>Class 6</option>
                <option>Class 7</option>
                <option>Class 8</option>
                <option>Class 9</option>
                <option>Class 10</option>
                <option>Class 11</option>
                <option>Class 12</option>
              </select>
            </label>
            <label className="field">
              Roll Number
              <input type="number" value={studentRoll} onChange={(event) => setStudentRoll(event.target.value)} />
            </label>
            <label className="field">
              Date of Birth
              <input type="date" value={studentDob} onChange={(event) => setStudentDob(event.target.value)} />
            </label>
            <label className="field">
              House
              <select value={studentHouse} onChange={(event) => setStudentHouse(event.target.value)}>
                <option>Ashoka</option>
                <option>Aravali</option>
                <option>Nilgiri</option>
                <option>Udaygiri</option>
                <option>Shivalik</option>
              </select>
            </label>
            <label className="field">
              Parent Phone
              <input
                value={studentParentPhone}
                onChange={(event) => setStudentParentPhone(event.target.value)}
                maxLength={13}
                placeholder="+9198..."
              />
            </label>
            <label className="field">
              Admission Year
              <input
                type="number"
                value={studentAdmissionYear}
                onChange={(event) => setStudentAdmissionYear(event.target.value)}
              />
            </label>
          </div>
          <div className="section-actions">
            <button className="app__button app__button--primary" onClick={createStudent}>Add student</button>
          </div>
          {students.length > 0 ? (
            <div className="student-list">
              {students.map((student) => (
                <div className="student-item" key={student.id}>
                  <strong>{student.full_name}</strong>
                  <p>{student.class_label} • Roll {student.roll_number} • House {student.house || '-'}</p>
                  <p>Parent: {student.parent_phone || '-'} • DOB: {student.date_of_birth?.slice(0, 10)}</p>
                </div>
              ))}
            </div>
          ) : (
            <div className="empty-state">No students loaded for selected class yet.</div>
          )}
        </section>

        <section className="card card--wide">
          <div className="card__header">
            <div>
              <h2>Upload Scores (Excel/CSV)</h2>
              <p>Columns: Subject, Roll No, Student Name, Marks.</p>
            </div>
            <button className="app__button">Download template</button>
          </div>
          <div className="form-grid">
            <label className="field">
              Class
              <select value={uploadClass} onChange={(event) => setUploadClass(event.target.value)}>
                <option>Class 6</option>
                <option>Class 7</option>
                <option>Class 8</option>
                <option>Class 9</option>
                <option>Class 10</option>
                <option>Class 11</option>
                <option>Class 12</option>
              </select>
            </label>
            <label className="field">
              Exam Name
              <input
                type="text"
                value={uploadExam}
                onChange={(event) => setUploadExam(event.target.value)}
                placeholder="Term 1 - Quarterly"
              />
            </label>
            <label className="field">
              Exam Date
              <input type="date" value={uploadDate} onChange={(event) => setUploadDate(event.target.value)} />
            </label>
            <label className="field">
              Term
              <select value={uploadTerm} onChange={(event) => setUploadTerm(event.target.value)}>
                <option>Term 1</option>
                <option>Term 2</option>
                <option>Term 3</option>
              </select>
            </label>
          </div>
          <div className="file-row">
            <input
              type="file"
              accept=".csv,.xlsx"
              onChange={(event) => setUploadFile(event.target.files?.[0] ?? null)}
            />
            <button className="app__button app__button--primary" onClick={handleUploadScores}>
              Upload file
            </button>
          </div>
          <div className="hint">
            Uploads go to admin for approval before publishing.
          </div>
        </section>

        <section className="card card--wide">
          <div className="card__header">
            <div>
              <h2>Manual Score Entry</h2>
              <p>Quick edits for individual students and subjects.</p>
            </div>
            <button className="app__button">Save draft</button>
          </div>
          <div className="form-grid">
            <label className="field">
              Class
              <select value={manualClass} onChange={(event) => setManualClass(event.target.value)}>
                <option>Class 6</option>
                <option>Class 7</option>
                <option>Class 8</option>
                <option>Class 9</option>
                <option>Class 10</option>
                <option>Class 11</option>
                <option>Class 12</option>
              </select>
            </label>
            <label className="field">
              Subject
              <input
                type="text"
                value={manualSubject}
                onChange={(event) => setManualSubject(event.target.value)}
                placeholder="Mathematics"
              />
            </label>
            <label className="field">
              Max Marks
              <input
                type="number"
                value={manualMaxMarks}
                onChange={(event) => setManualMaxMarks(Number(event.target.value))}
                placeholder="100"
              />
            </label>
            <label className="field">
              Exam
              <input
                type="text"
                value={manualExam}
                onChange={(event) => setManualExam(event.target.value)}
                placeholder="Term 1 - Quarterly"
              />
            </label>
            <label className="field">
              Exam Date
              <input type="date" value={manualDate} onChange={(event) => setManualDate(event.target.value)} />
            </label>
            <label className="field">
              Term
              <select value={manualTerm} onChange={(event) => setManualTerm(event.target.value)}>
                <option>Term 1</option>
                <option>Term 2</option>
                <option>Term 3</option>
              </select>
            </label>
          </div>
          <table className="score-table">
            <thead>
              <tr>
                <th>Roll No</th>
                <th>Student Name</th>
                <th>Score</th>
                <th>Grade</th>
              </tr>
            </thead>
            <tbody>
              {manualRows.map((row, index) => (
                <tr key={`${row.roll}-${index}`}>
                  <td>
                    <input
                      type="text"
                      value={row.roll}
                      onChange={(event) => updateManualRow(index, 'roll', event.target.value)}
                    />
                  </td>
                  <td>
                    <input
                      type="text"
                      value={row.name}
                      onChange={(event) => updateManualRow(index, 'name', event.target.value)}
                    />
                  </td>
                  <td>
                    <input
                      type="number"
                      value={row.score}
                      onChange={(event) => updateManualRow(index, 'score', event.target.value)}
                    />
                  </td>
                  <td>
                    <input
                      type="text"
                      value={row.grade}
                      onChange={(event) => updateManualRow(index, 'grade', event.target.value)}
                    />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          <button className="app__button app__button--primary" onClick={handleManualSubmit}>
            Submit for approval
          </button>
        </section>

        <section className="card">
          <h2>Announcements</h2>
          <p>Create and publish school-wide updates for parents.</p>
          <div className="section-actions">
            <button className="app__button" onClick={loadAnnouncements}>Refresh list</button>
          </div>
          <div className="field">
            Title
            <input
              type="text"
              value={annTitle}
              onChange={(event) => setAnnTitle(event.target.value)}
              placeholder="Winter Break Schedule"
            />
          </div>
          <div className="field">
            Category
            <input
              type="text"
              value={annCategory}
              onChange={(event) => setAnnCategory(event.target.value)}
              placeholder="Academic"
            />
          </div>
          <div className="field">
            Priority
            <select value={annPriority} onChange={(event) => setAnnPriority(event.target.value)}>
              <option>High</option>
              <option>Medium</option>
              <option>Low</option>
            </select>
          </div>
          <div className="field">
            Message
            <textarea
              rows={4}
              value={annMessage}
              onChange={(event) => setAnnMessage(event.target.value)}
              placeholder="Add announcement details"
            />
          </div>
          <button className="app__button app__button--primary" onClick={handlePublishAnnouncement}>
            Create draft
          </button>
          {announcements.length > 0 ? (
            <div className="announcement-list">
              {announcements.map((item) => (
                <div className="announcement-item" key={String(item.id)}>
                  <div>
                    <strong>{String(item.title)}</strong>
                    <p>{String(item.category)} • {String(item.priority)}</p>
                  </div>
                  {item.published ? (
                    <span className="badge badge--live">Published</span>
                  ) : (
                    <button
                      className="app__button app__button--primary"
                      onClick={() => publishAnnouncement(String(item.id))}
                    >
                      Publish
                    </button>
                  )}
                </div>
              ))}
            </div>
          ) : null}
        </section>

        <section className="card">
          <h2>Events CMS</h2>
          <p>Create/publish events shown in mobile dashboard and events tab.</p>
          <div className="section-actions">
            <button className="app__button" onClick={loadEvents}>Refresh events</button>
          </div>
          <div className="field">
            Title
            <input
              type="text"
              value={eventTitle}
              onChange={(event) => setEventTitle(event.target.value)}
              placeholder="Annual Sports Day"
            />
          </div>
          <div className="field">
            Description
            <textarea
              rows={3}
              value={eventDescription}
              onChange={(event) => setEventDescription(event.target.value)}
              placeholder="Describe the event for parents"
            />
          </div>
          <div className="form-grid">
            <label className="field">
              Event Date
              <input type="date" value={eventDate} onChange={(event) => setEventDate(event.target.value)} />
            </label>
            <label className="field">
              Start Time
              <input value={eventStartTime} onChange={(event) => setEventStartTime(event.target.value)} placeholder="10:00 AM" />
            </label>
            <label className="field">
              End Time
              <input value={eventEndTime} onChange={(event) => setEventEndTime(event.target.value)} placeholder="1:00 PM" />
            </label>
            <label className="field">
              Category
              <input value={eventCategory} onChange={(event) => setEventCategory(event.target.value)} placeholder="Academic" />
            </label>
            <label className="field">
              Location
              <input value={eventLocation} onChange={(event) => setEventLocation(event.target.value)} placeholder="Main Hall" />
            </label>
            <label className="field">
              Audience
              <input value={eventAudience} onChange={(event) => setEventAudience(event.target.value)} placeholder="All Students" />
            </label>
          </div>
          <button className="app__button app__button--primary" onClick={createEvent}>
            Create event draft
          </button>
          {events.length > 0 ? (
            <div className="announcement-list">
              {events.map((item) => (
                <div className="announcement-item" key={item.id}>
                  <div>
                    <strong>{item.title}</strong>
                    <p>{formatDate(item.event_date)} • {item.category || 'General'}</p>
                  </div>
                  {item.published ? (
                    <span className="badge badge--live">Published</span>
                  ) : (
                    <button className="app__button app__button--primary" onClick={() => publishEvent(item.id)}>
                      Publish
                    </button>
                  )}
                </div>
              ))}
            </div>
          ) : (
            <div className="empty-state">No events created yet.</div>
          )}
        </section>

        <section className="card card--wide">
          <h2>Mobile App Config</h2>
          <p>Feature flags and dashboard widgets are delivered from backend (no APK rebuild needed for these changes).</p>
          <div className="section-actions">
            <button className="app__button" onClick={loadAppConfig}>Load config</button>
            <button className="app__button app__button--primary" onClick={saveAppConfig}>Save config</button>
          </div>
          <div className="form-grid">
            <label className="field">
              <input
                type="checkbox"
                checked={Boolean(featureFlags.show_events)}
                onChange={(event) => setFlag('show_events', event.target.checked)}
              />
              Show events
            </label>
            <label className="field">
              <input
                type="checkbox"
                checked={Boolean(featureFlags.show_announcements)}
                onChange={(event) => setFlag('show_announcements', event.target.checked)}
              />
              Show announcements
            </label>
            <label className="field">
              <input
                type="checkbox"
                checked={Boolean(featureFlags.show_attendance)}
                onChange={(event) => setFlag('show_attendance', event.target.checked)}
              />
              Show attendance (future)
            </label>
            <label className="field">
              <input
                type="checkbox"
                checked={Boolean(featureFlags.show_academic_tab)}
                onChange={(event) => setFlag('show_academic_tab', event.target.checked)}
              />
              Show academic tab
            </label>
          </div>
          <table className="score-table">
            <thead>
              <tr>
                <th>Key</th>
                <th>Label</th>
                <th>Value</th>
                <th>Hint</th>
                <th>Icon</th>
              </tr>
            </thead>
            <tbody>
              {dashboardWidgets.map((widget, index) => (
                <tr key={`${widget.key}-${index}`}>
                  <td><input value={widget.key} onChange={(event) => updateWidget(index, 'key', event.target.value)} /></td>
                  <td><input value={widget.label} onChange={(event) => updateWidget(index, 'label', event.target.value)} /></td>
                  <td><input value={widget.value} onChange={(event) => updateWidget(index, 'value', event.target.value)} /></td>
                  <td><input value={widget.hint} onChange={(event) => updateWidget(index, 'hint', event.target.value)} /></td>
                  <td><input value={widget.icon} onChange={(event) => updateWidget(index, 'icon', event.target.value)} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>

        <section className="card">
          <h2>Approvals</h2>
          <p>Approve parent-link requests directly from UI.</p>
          <div className="section-actions">
            <button className="app__button" onClick={loadPendingLinks}>Load requests</button>
          </div>
          {pendingLinks.length === 0 ? (
            <div className="empty-state">No pending parent-link requests.</div>
          ) : (
            pendingLinks.map((link) => (
              <div className="approval-item" key={link.id}>
                <div>
                  <strong>Parent Link Request</strong>
                  <p>
                    Parent: {link.parent_name || 'Unknown'} ({link.parent_phone || link.parent_id})
                  </p>
                  <p>
                    Student: {link.student_name || link.student_id} • {link.class_label} • Roll {link.roll_number}
                  </p>
                  <p>Requested: {formatDate(link.created_at)}</p>
                </div>
                <button
                  className="app__button app__button--primary"
                  onClick={() => approveParentLink(link.id)}
                >
                  Approve
                </button>
              </div>
            ))
          )}
        </section>
      </main>
      {status ? <div className="status-bar">{status}</div> : null}
    </div>
  );
}

function formatDate(value: string) {
  if (!value) return 'Unknown';
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return 'Unknown';
  return parsed.toLocaleString();
}
