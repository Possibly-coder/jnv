import { useEffect, useMemo, useRef, useState } from 'react';
import {
  ConfirmationResult,
  onAuthStateChanged,
  RecaptchaVerifier,
  signInWithPhoneNumber,
  signInWithPopup,
  signOut,
} from 'firebase/auth';
import './styles.css';
import { firebaseAuth, firebaseConfigured, googleProvider } from './firebase';

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

type AnnouncementRecord = {
  id: string;
  title: string;
  content?: string;
  category?: string;
  priority?: string;
  published?: boolean;
};

function isEventRecord(value: unknown): value is EventRecord {
  if (!value || typeof value !== 'object') return false;
  const item = value as Record<string, unknown>;
  return typeof item.id === 'string' && typeof item.title === 'string';
}

function isAnnouncementRecord(value: unknown): value is AnnouncementRecord {
  if (!value || typeof value !== 'object') return false;
  const item = value as Record<string, unknown>;
  return typeof item.id === 'string' && typeof item.title === 'string';
}

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
  min_supported_version?: string;
  force_update_message?: string;
};

type UserRecord = {
  id: string;
  full_name: string;
  phone: string;
  role: string;
  email: string;
};

type AuditLogRecord = {
  id: string;
  action: string;
  user_id: string;
  user_role: string;
  created_at: string;
  payload: string;
};

const API_BASE_URL =
  (import.meta.env.VITE_API_BASE_URL as string | undefined)
    ?.trim()
    .replace(/\/+$/, '') || 'https://jnv-web.onrender.com';

export default function App() {
  const [token, setToken] = useState('');
  const [authUserLabel, setAuthUserLabel] = useState('');
  const [authBusy, setAuthBusy] = useState(false);
  const [phoneAuthBusy, setPhoneAuthBusy] = useState(false);
  const [phoneNumber, setPhoneNumber] = useState('');
  const [phoneOtp, setPhoneOtp] = useState('');
  const [phoneConfirmation, setPhoneConfirmation] = useState<ConfirmationResult | null>(null);
  const [status, setStatus] = useState('');
  const recaptchaRef = useRef<RecaptchaVerifier | null>(null);

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
  const [announcements, setAnnouncements] = useState<AnnouncementRecord[]>([]);
  const [pendingLinks, setPendingLinks] = useState<ParentLink[]>([]);
  const [students, setStudents] = useState<StudentRecord[]>([]);
  const [studentFullName, setStudentFullName] = useState('');
  const [studentClass, setStudentClass] = useState('Class 10');
  const [studentRoll, setStudentRoll] = useState('');
  const [studentDob, setStudentDob] = useState('');
  const [studentHouse, setStudentHouse] = useState('Ashoka');
  const [studentParentPhone, setStudentParentPhone] = useState('');
  const [studentAdmissionYear, setStudentAdmissionYear] = useState(`${new Date().getFullYear()}`);
  const [studentUploadFile, setStudentUploadFile] = useState<File | null>(null);
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
  const [minSupportedVersion, setMinSupportedVersion] = useState('');
  const [forceUpdateMessage, setForceUpdateMessage] = useState('');
  const [users, setUsers] = useState<UserRecord[]>([]);
  const [auditLogs, setAuditLogs] = useState<AuditLogRecord[]>([]);

  const authHeader = useMemo(() => ({
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  }), [token]);

  const authOnlyHeader = useMemo(() => ({
    Authorization: `Bearer ${token}`,
  }), [token]);

  const safeEvents = useMemo(
    () => events.filter((item) => isEventRecord(item)),
    [events],
  );
  const safeAnnouncements = useMemo(
    () => announcements.filter((item) => isAnnouncementRecord(item)),
    [announcements],
  );

  useEffect(() => {
    if (!firebaseConfigured || !firebaseAuth) return;
    const unsub = onAuthStateChanged(firebaseAuth, async (user) => {
      if (!user) {
        setToken('');
        setAuthUserLabel('');
        return;
      }
      const idToken = await user.getIdToken(true);
      setToken(idToken);
      setAuthUserLabel(user.email || user.phoneNumber || user.uid);
    });
    return () => unsub();
  }, []);

  useEffect(() => {
    return () => {
      if (recaptchaRef.current) {
        recaptchaRef.current.clear();
        recaptchaRef.current = null;
      }
    };
  }, []);

  const loginWithGoogle = async () => {
    if (!firebaseConfigured || !firebaseAuth) {
      setStatus('Firebase web config missing. Set VITE_FIREBASE_* in web/.env.');
      return;
    }
    try {
      setAuthBusy(true);
      await signInWithPopup(firebaseAuth, googleProvider);
      setStatus('Signed in with Firebase.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    } finally {
      setAuthBusy(false);
    }
  };

  const logoutFirebase = async () => {
    if (!firebaseAuth) return;
    await signOut(firebaseAuth);
    setPhoneConfirmation(null);
    setPhoneOtp('');
    setPhoneNumber('');
    setStatus('Signed out.');
  };

  const normalizedPhone = () => {
    const raw = phoneNumber.trim();
    if (raw.startsWith('+')) return raw;
    const digits = raw.replace(/[^0-9]/g, '');
    if (digits.startsWith('91') && digits.length === 12) {
      return `+${digits}`;
    }
    return `+91${digits}`;
  };

  const sendPhoneOtp = async () => {
    if (!firebaseConfigured || !firebaseAuth) {
      setStatus('Firebase web config missing. Set VITE_FIREBASE_* in web/.env.');
      return;
    }
    const phone = normalizedPhone();
    if (phone.replace(/[^0-9]/g, '').length < 12) {
      setStatus('Enter a valid phone number.');
      return;
    }
    try {
      setPhoneAuthBusy(true);
      if (recaptchaRef.current) {
        recaptchaRef.current.clear();
        recaptchaRef.current = null;
      }
      recaptchaRef.current = new RecaptchaVerifier(firebaseAuth, 'recaptcha-container', {
        size: 'invisible',
      });
      const confirmation = await signInWithPhoneNumber(firebaseAuth, phone, recaptchaRef.current);
      setPhoneConfirmation(confirmation);
      setStatus('OTP sent to mobile number.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    } finally {
      setPhoneAuthBusy(false);
    }
  };

  const verifyPhoneOtp = async () => {
    if (!phoneConfirmation) {
      setStatus('Send OTP first.');
      return;
    }
    if (phoneOtp.trim().length !== 6) {
      setStatus('Enter 6-digit OTP.');
      return;
    }
    try {
      setPhoneAuthBusy(true);
      await phoneConfirmation.confirm(phoneOtp.trim());
      setPhoneOtp('');
      setPhoneConfirmation(null);
      setStatus('Signed in with phone OTP.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    } finally {
      setPhoneAuthBusy(false);
    }
  };

  const postJSON = async (path: string, payload: unknown) => {
    if (!token) {
      throw new Error('Please sign in first.');
    }
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
    if (!token) {
      throw new Error('Please sign in first.');
    }
    const res = await fetch(`${API_BASE_URL}${path}`, {
      headers: authHeader,
    });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(body || res.statusText);
    }
    return res.json();
  };

  const deleteJSON = async (path: string) => {
    if (!token) {
      throw new Error('Please sign in first.');
    }
    const res = await fetch(`${API_BASE_URL}${path}`, {
      method: 'DELETE',
      headers: authHeader,
    });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(body || res.statusText);
    }
    return res.text();
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
      const response = await getJSON('/api/v1/announcements');
      const items = Array.isArray(response)
        ? response
        : (response && typeof response === 'object' && Array.isArray((response as Record<string, unknown>).items))
          ? ((response as Record<string, unknown>).items as unknown[])
          : [];
      setAnnouncements(items.filter((item) => isAnnouncementRecord(item)));
      setStatus('Announcements loaded.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
      setAnnouncements([]);
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

  const deleteAnnouncement = async (id: string) => {
    if (!window.confirm('Delete this announcement? This cannot be undone.')) return;
    try {
      setStatus('Deleting announcement...');
      await deleteJSON(`/api/v1/announcements/${id}`);
      await loadAnnouncements();
      setStatus('Announcement deleted.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    }
  };

  const loadEvents = async () => {
    try {
      setStatus('Loading events...');
      const response = await getJSON('/api/v1/events');
      const items = Array.isArray(response)
        ? response
        : (response && typeof response === 'object' && Array.isArray((response as Record<string, unknown>).items))
          ? ((response as Record<string, unknown>).items as unknown[])
          : [];
      setEvents(items.filter((item) => isEventRecord(item)));
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

  const deleteEvent = async (id: string) => {
    if (!window.confirm('Delete this event? This cannot be undone.')) return;
    try {
      setStatus('Deleting event...');
      await deleteJSON(`/api/v1/events/${id}`);
      await loadEvents();
      setStatus('Event deleted.');
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
      setMinSupportedVersion(config.min_supported_version ?? '');
      setForceUpdateMessage(config.force_update_message ?? '');
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
        min_supported_version: minSupportedVersion.trim(),
        force_update_message: forceUpdateMessage.trim(),
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

  const loadUsers = async () => {
    try {
      setStatus('Loading users...');
      const items = await getJSON('/api/v1/users');
      setUsers(Array.isArray(items) ? (items as UserRecord[]) : []);
      setStatus('Users loaded.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    }
  };

  const updateUserRole = async (id: string, role: string) => {
    try {
      setStatus('Updating user role...');
      await postJSON(`/api/v1/users/${id}/role`, { role });
      setUsers((prev) => prev.map((u) => (u.id === id ? { ...u, role } : u)));
      setStatus('User role updated.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    }
  };

  const loadAuditLogs = async () => {
    try {
      setStatus('Loading audit logs...');
      const items = await getJSON('/api/v1/audit-logs?limit=200');
      setAuditLogs(Array.isArray(items) ? (items as AuditLogRecord[]) : []);
      setStatus('Audit logs loaded.');
    } catch (err) {
      setStatus(`Error: ${(err as Error).message}`);
    }
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

  const handleUploadStudents = async () => {
    try {
      if (!studentUploadFile) {
        setStatus('Please select a CSV/XLSX file for student upload.');
        return;
      }
      setStatus('Uploading student master data...');
      const formData = new FormData();
      formData.append('file', studentUploadFile);
      const res = await fetch(`${API_BASE_URL}/api/v1/students/upload`, {
        method: 'POST',
        headers: authOnlyHeader,
        body: formData,
      });
      const body = await res.json();
      if (!res.ok) {
        const errors = Array.isArray(body.errors) ? body.errors.join(', ') : res.statusText;
        throw new Error(errors);
      }
      const inserted = Number(body.inserted ?? 0);
      const failed = Number(body.failed ?? 0);
      const errors = Array.isArray(body.errors) ? body.errors.slice(0, 5).join(' | ') : '';
      setStatus(`Student upload complete. Inserted: ${inserted}, Failed: ${failed}${errors ? `, Errors: ${errors}` : ''}`);
      setStudentUploadFile(null);
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

  const downloadCsvTemplate = (filename: string, content: string) => {
    const blob = new Blob([content], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.setAttribute('download', filename);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  };

  const downloadStudentTemplate = () => {
    const content = [
      'full_name,class_label,roll_number,date_of_birth,house,parent_phone,admission_year',
      'Aarav Sharma,Class 8,12,2012-07-14,Aravali,+919812345678,2023',
      'Anaya Verma,Class 8,14,2012-03-09,Nilgiri,+919876543210,2023',
    ].join('\n');
    downloadCsvTemplate('student_upload_template.csv', content);
  };

  const downloadScoreTemplate = () => {
    const content = [
      'subject,roll_no,student_name,score,max_score,grade',
      'Mathematics,12,Aarav Sharma,88,100,A',
      'Science,12,Aarav Sharma,84,100,A',
      'English,14,Anaya Verma,91,100,A+',
    ].join('\n');
    downloadCsvTemplate('score_upload_template.csv', content);
  };

  return (
    <div className="app">
      <header className="app__header">
        <div className="app__brand">
          <img className="app__logo" src="/jnv-logo.png" alt="JNV logo" />
          <div>
            <h1>JNV Admin Portal</h1>
            <p>Scores, announcements, and approvals</p>
          </div>
        </div>
        <div className="header-actions">
          <span className="api-badge">API: {API_BASE_URL}</span>
          {token ? (
            <>
              <span className="api-badge">User: {authUserLabel || 'Authenticated'}</span>
              <button className="app__button" onClick={logoutFirebase}>Logout</button>
            </>
          ) : (
            <>
              <button className="app__button app__button--primary" onClick={loginWithGoogle} disabled={authBusy}>
                {authBusy ? 'Signing in...' : 'Sign in with Google'}
              </button>
              <input
                className="token-input"
                value={phoneNumber}
                onChange={(event) => setPhoneNumber(event.target.value)}
                placeholder="Phone (+91...)"
              />
              {phoneConfirmation ? (
                <>
                  <input
                    className="token-input"
                    value={phoneOtp}
                    onChange={(event) => setPhoneOtp(event.target.value)}
                    placeholder="OTP"
                  />
                  <button className="app__button app__button--primary" onClick={verifyPhoneOtp} disabled={phoneAuthBusy}>
                    {phoneAuthBusy ? 'Verifying...' : 'Verify OTP'}
                  </button>
                </>
              ) : (
                <button className="app__button" onClick={sendPhoneOtp} disabled={phoneAuthBusy}>
                  {phoneAuthBusy ? 'Sending...' : 'Login via Phone'}
                </button>
              )}
              <div id="recaptcha-container" />
            </>
          )}
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
            <button className="app__button" onClick={downloadStudentTemplate}>Download template</button>
          </div>
          <div className="file-row">
            <input
              type="file"
              accept=".csv,.xlsx"
              onChange={(event) => setStudentUploadFile(event.target.files?.[0] ?? null)}
            />
            <button className="app__button app__button--primary" onClick={handleUploadStudents}>
              Upload students
            </button>
          </div>
          <div className="hint">
            Bulk template columns: full_name,class_label,roll_number,date_of_birth,house,parent_phone,admission_year
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
            <button className="app__button" onClick={downloadScoreTemplate}>Download template</button>
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
          {safeAnnouncements.length > 0 ? (
            <div className="announcement-list">
              {safeAnnouncements.map((item) => (
                <div className="announcement-item" key={String(item.id)}>
                  <div>
                    <strong>{String(item.title)}</strong>
                    <p>{String(item.category)} • {String(item.priority)}</p>
                  </div>
                  {item.published ? (
                    <span className="badge badge--live">Published</span>
                  ) : (
                    <div className="item-actions">
                      <button
                        className="app__button app__button--primary"
                        onClick={() => publishAnnouncement(String(item.id))}
                      >
                        Publish
                      </button>
                      <button
                        className="app__button app__button--danger"
                        onClick={() => deleteAnnouncement(String(item.id))}
                      >
                        Delete
                      </button>
                    </div>
                  )}
                  {item.published ? (
                    <button
                      className="app__button app__button--danger"
                      onClick={() => deleteAnnouncement(String(item.id))}
                    >
                      Delete
                    </button>
                  ) : null}
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
          {safeEvents.length > 0 ? (
            <div className="announcement-list">
              {safeEvents.map((item) => (
                <div className="announcement-item" key={item.id}>
                  <div>
                    <strong>{item.title}</strong>
                    <p>{formatDate(item.event_date)} • {item.category || 'General'}</p>
                  </div>
                  {item.published ? (
                    <div className="item-actions">
                      <span className="badge badge--live">Published</span>
                      <button className="app__button app__button--danger" onClick={() => deleteEvent(item.id)}>
                        Delete
                      </button>
                    </div>
                  ) : (
                    <div className="item-actions">
                      <button className="app__button app__button--primary" onClick={() => publishEvent(item.id)}>
                        Publish
                      </button>
                      <button className="app__button app__button--danger" onClick={() => deleteEvent(item.id)}>
                        Delete
                      </button>
                    </div>
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
            <label className="field">
              Min supported app version
              <input
                value={minSupportedVersion}
                onChange={(event) => setMinSupportedVersion(event.target.value)}
                placeholder="e.g. 1.0.3"
              />
            </label>
            <label className="field">
              Force update message
              <input
                value={forceUpdateMessage}
                onChange={(event) => setForceUpdateMessage(event.target.value)}
                placeholder="Please update app to continue"
              />
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
          <h2>User Role Management</h2>
          <p>Manage school users and update roles for access control.</p>
          <div className="section-actions">
            <button className="app__button" onClick={loadUsers}>Load users</button>
          </div>
          {users.length === 0 ? (
            <div className="empty-state">No users loaded yet.</div>
          ) : (
            <div className="announcement-list">
              {users.map((user) => (
                <div className="announcement-item" key={user.id}>
                  <div>
                    <strong>{user.full_name || 'Unknown'}</strong>
                    <p>{user.phone} • {user.email || '-'}</p>
                  </div>
                  <select
                    value={user.role}
                    onChange={(event) => updateUserRole(user.id, event.target.value)}
                  >
                    <option value="parent">parent</option>
                    <option value="teacher">teacher</option>
                    <option value="staff">staff</option>
                    <option value="admin">admin</option>
                  </select>
                </div>
              ))}
            </div>
          )}
        </section>

        <section className="card card--wide">
          <h2>Audit Logs</h2>
          <p>Track sensitive actions performed by admins/staff.</p>
          <div className="section-actions">
            <button className="app__button" onClick={loadAuditLogs}>Load logs</button>
          </div>
          {auditLogs.length === 0 ? (
            <div className="empty-state">No audit logs loaded yet.</div>
          ) : (
            <table className="score-table">
              <thead>
                <tr>
                  <th>Time</th>
                  <th>Action</th>
                  <th>User</th>
                  <th>Role</th>
                  <th>Payload</th>
                </tr>
              </thead>
              <tbody>
                {auditLogs.map((log) => (
                  <tr key={log.id}>
                    <td>{formatDate(log.created_at)}</td>
                    <td>{log.action}</td>
                    <td>{log.user_id || '-'}</td>
                    <td>{log.user_role || '-'}</td>
                    <td style={{ maxWidth: 360, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                      {log.payload}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
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
