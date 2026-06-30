-- 允许群系统提示消息类型
ALTER TABLE messages DROP CONSTRAINT IF EXISTS messages_type_check;
ALTER TABLE messages ADD CONSTRAINT messages_type_check
    CHECK (type IN ('text', 'image', 'file', 'announcement', 'system'));
