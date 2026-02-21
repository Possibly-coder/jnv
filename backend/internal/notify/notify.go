package notify

import "context"

type Sender interface {
	SendToSchoolParents(ctx context.Context, schoolID, title, body string, data map[string]string) error
}
