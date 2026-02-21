package notify

import "context"

type NoopSender struct{}

func (NoopSender) SendToSchoolParents(_ context.Context, _ string, _ string, _ string, _ map[string]string) error {
	return nil
}
