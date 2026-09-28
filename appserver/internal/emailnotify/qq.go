package emailnotify

import "context"

// FuncQQSuppressor adapts a function to QQSuppressor.
type FuncQQSuppressor func(ctx context.Context, userID string) (bool, error)

func (f FuncQQSuppressor) SuppressEmail(ctx context.Context, userID string) (bool, error) {
	if f == nil {
		return false, nil
	}
	return f(ctx, userID)
}
