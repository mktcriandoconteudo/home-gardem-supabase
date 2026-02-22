-- ============================================================================
-- HOME GARDEN MANUAL - COMPLETE DATABASE SCHEMA EXPORT
-- ============================================================================
-- Generated for external Supabase project migration
-- Execute this SQL in your Supabase SQL Editor
-- ============================================================================

-- ============================================================================
-- SECTION 1: EXTENSIONS
-- ============================================================================

-- Enable required extensions (usually already enabled in Supabase)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_cron";

-- ============================================================================
-- SECTION 2: CUSTOM TYPES (ENUMS)
-- ============================================================================

-- App role enum for user permissions
DO $$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'user');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- ============================================================================
-- SECTION 3: HELPER FUNCTIONS
-- ============================================================================

-- Function to check if a user has a specific role
CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role app_role)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role = _role
  )
$$;

-- Function to check if current authenticated user is admin
CREATE OR REPLACE FUNCTION public.is_current_user_admin()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid()
    AND role = 'admin'
  )
$$;

-- Function to automatically update updated_at column
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- Function to handle new user registration (creates profile and assigns role)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  INSERT INTO public.profiles (user_id, email)
  VALUES (NEW.id, NEW.email);
  
  INSERT INTO public.user_roles (user_id, role)
  VALUES (NEW.id, 'user');
  
  RETURN NEW;
END;
$$;

-- Function to increment article likes with duplicate prevention
CREATE OR REPLACE FUNCTION public.increment_article_likes(p_article_id uuid, p_ip_hash text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  new_count INTEGER;
BEGIN
  -- Try to insert the like (will fail if already exists due to UNIQUE constraint)
  INSERT INTO article_likes (article_id, ip_hash)
  VALUES (p_article_id, p_ip_hash);
  
  -- Increment the counter
  UPDATE content_articles 
  SET likes_count = likes_count + 1
  WHERE id = p_article_id
  RETURNING likes_count INTO new_count;
  
  RETURN new_count;
EXCEPTION
  WHEN unique_violation THEN
    -- Already liked, return current count
    SELECT likes_count INTO new_count FROM content_articles WHERE id = p_article_id;
    RETURN new_count;
END;
$$;

-- Function to register affiliate banner clicks
CREATE OR REPLACE FUNCTION public.register_affiliate_click(
  p_article_id uuid, 
  p_ip_hash text, 
  p_user_agent text DEFAULT NULL, 
  p_referrer text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  new_count INTEGER;
BEGIN
  -- Insert the click record
  INSERT INTO affiliate_banner_clicks (article_id, ip_hash, user_agent, referrer)
  VALUES (p_article_id, p_ip_hash, p_user_agent, p_referrer);
  
  -- Increment the counter on the article
  UPDATE content_articles 
  SET affiliate_clicks_count = affiliate_clicks_count + 1
  WHERE id = p_article_id
  RETURNING affiliate_clicks_count INTO new_count;
  
  RETURN COALESCE(new_count, 0);
END;
$$;

-- Function to get cron job history (for image queue processing)
CREATE OR REPLACE FUNCTION public.get_cron_job_history()
RETURNS TABLE(
  runid bigint, 
  job_pid integer, 
  status text, 
  return_message text, 
  start_time timestamp with time zone, 
  end_time timestamp with time zone, 
  duration_ms numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    jrd.runid,
    jrd.job_pid,
    jrd.status,
    jrd.return_message,
    jrd.start_time,
    jrd.end_time,
    CASE 
      WHEN jrd.end_time IS NOT NULL 
      THEN EXTRACT(EPOCH FROM (jrd.end_time - jrd.start_time)) * 1000
      ELSE NULL
    END as duration_ms
  FROM cron.job_run_details jrd
  INNER JOIN cron.job j ON j.jobid = jrd.jobid
  WHERE j.jobname = 'process-image-queue-every-5-min'
  ORDER BY jrd.start_time DESC
  LIMIT 50;
END;
$$;

-- ============================================================================
-- SECTION 4: TABLES
-- ============================================================================

-- -----------------------------------------------------------------------------
-- 4.1 User Management Tables
-- -----------------------------------------------------------------------------

-- Profiles table - stores additional user information
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL UNIQUE,
  email text,
  username text,
  avatar_url text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

-- User roles table - manages user permissions
CREATE TABLE IF NOT EXISTS public.user_roles (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL,
  role app_role NOT NULL DEFAULT 'user'::app_role,
  created_at timestamp with time zone DEFAULT now(),
  UNIQUE(user_id, role)
);

-- Audit logs table - tracks admin actions
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL,
  action_type text NOT NULL,
  target_user_id uuid,
  details jsonb DEFAULT '{}'::jsonb,
  ip_address text,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- 4.2 Content Tables
-- -----------------------------------------------------------------------------

-- Main articles table
CREATE TABLE IF NOT EXISTS public.content_articles (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  author_id uuid NOT NULL,
  title text NOT NULL,
  slug text UNIQUE,
  excerpt text,
  body text,
  keywords text,
  category text DEFAULT 'decoracao'::text,
  category_slug text,
  tags text[] DEFAULT '{}'::text[],
  cover_image text,
  gallery_images jsonb DEFAULT '[]'::jsonb,
  external_links jsonb DEFAULT '[]'::jsonb,
  read_time text DEFAULT '5 min'::text,
  status text DEFAULT 'draft'::text,
  published_at timestamp with time zone,
  likes_count integer NOT NULL DEFAULT 0,
  affiliate_banner_enabled boolean DEFAULT false,
  affiliate_banner_url text,
  affiliate_banner_image text,
  affiliate_banner_image_mobile text,
  affiliate_clicks_count integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

-- Article images metadata table
CREATE TABLE IF NOT EXISTS public.article_images (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  article_id uuid,
  image_type text NOT NULL,
  storage_path text NOT NULL,
  public_url text NOT NULL,
  original_prompt text,
  format text DEFAULT 'webp'::text,
  width integer,
  height integer,
  file_size integer,
  image_index integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT now()
);

-- Article views tracking
CREATE TABLE IF NOT EXISTS public.article_views (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  article_id uuid NOT NULL,
  ip_hash text,
  viewed_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Article likes tracking
CREATE TABLE IF NOT EXISTS public.article_likes (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  article_id uuid NOT NULL,
  ip_hash text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  UNIQUE(article_id, ip_hash)
);

-- Affiliate banner clicks tracking
CREATE TABLE IF NOT EXISTS public.affiliate_banner_clicks (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  article_id uuid NOT NULL,
  ip_hash text,
  user_agent text,
  referrer text,
  clicked_at timestamp with time zone NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- 4.3 AI Generation Tables
-- -----------------------------------------------------------------------------

-- Generation history - tracks AI article generations
CREATE TABLE IF NOT EXISTS public.generation_history (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL,
  topic text NOT NULL,
  article_id uuid,
  article_title text,
  status text NOT NULL DEFAULT 'success'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Image generation queue
CREATE TABLE IF NOT EXISTS public.image_generation_queue (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  article_id uuid,
  image_type text NOT NULL,
  prompt text NOT NULL,
  status text NOT NULL DEFAULT 'pending'::text,
  result_url text,
  error_message text,
  image_index integer DEFAULT 0,
  retry_count integer DEFAULT 0,
  max_retries integer DEFAULT 3,
  priority integer DEFAULT 0,
  metadata jsonb DEFAULT '{}'::jsonb,
  next_retry_at timestamp with time zone,
  completed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

-- Image backup logs
CREATE TABLE IF NOT EXISTS public.image_backup_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  status text NOT NULL DEFAULT 'pending'::text,
  total_images integer NOT NULL DEFAULT 0,
  backed_up integer NOT NULL DEFAULT 0,
  failed integer NOT NULL DEFAULT 0,
  duration_ms integer,
  error_message text,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- 4.4 Contact & Communication Tables
-- -----------------------------------------------------------------------------

-- Contact messages from visitors
CREATE TABLE IF NOT EXISTS public.contact_messages (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name text NOT NULL,
  email text NOT NULL,
  subject text NOT NULL,
  message text NOT NULL,
  status text NOT NULL DEFAULT 'pending'::text,
  ip_hash text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Replies to contact messages
CREATE TABLE IF NOT EXISTS public.contact_message_replies (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id uuid NOT NULL,
  replied_by uuid NOT NULL,
  reply_text text NOT NULL,
  is_ai_generated boolean DEFAULT false,
  sent_via_email boolean DEFAULT false,
  replied_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Reply templates for contact messages
CREATE TABLE IF NOT EXISTS public.contact_reply_templates (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  title text NOT NULL,
  content text NOT NULL,
  category text DEFAULT 'general'::text,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- 4.5 Newsletter Tables
-- -----------------------------------------------------------------------------

-- Newsletter subscribers
CREATE TABLE IF NOT EXISTS public.newsletter_subscribers (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  email text NOT NULL UNIQUE,
  is_active boolean NOT NULL DEFAULT true,
  source text DEFAULT 'footer'::text,
  ip_hash text,
  subscribed_at timestamp with time zone NOT NULL DEFAULT now(),
  unsubscribed_at timestamp with time zone
);

-- Newsletter send history
CREATE TABLE IF NOT EXISTS public.newsletter_send_history (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  article_id uuid,
  article_slug text,
  article_title text NOT NULL,
  sent_by uuid,
  status text NOT NULL DEFAULT 'pending'::text,
  total_recipients integer NOT NULL DEFAULT 0,
  successful_sends integer NOT NULL DEFAULT 0,
  failed_sends integer NOT NULL DEFAULT 0,
  opened_count integer NOT NULL DEFAULT 0,
  clicked_count integer NOT NULL DEFAULT 0,
  error_message text,
  sent_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Newsletter email tracking (opens, clicks)
CREATE TABLE IF NOT EXISTS public.newsletter_email_tracking (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  send_history_id uuid NOT NULL,
  subscriber_email text NOT NULL,
  tracking_token uuid NOT NULL DEFAULT gen_random_uuid(),
  status text NOT NULL DEFAULT 'sent'::text,
  sent_at timestamp with time zone DEFAULT now(),
  opened_at timestamp with time zone,
  clicked_at timestamp with time zone
);

-- -----------------------------------------------------------------------------
-- 4.6 Email & Notification Tables
-- -----------------------------------------------------------------------------

-- Email templates
CREATE TABLE IF NOT EXISTS public.email_templates (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name varchar NOT NULL,
  description text,
  category varchar NOT NULL DEFAULT 'contact_reply'::varchar,
  html_template text NOT NULL,
  is_active boolean DEFAULT true,
  is_default boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

-- System notifications
CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL,
  title text NOT NULL,
  message text NOT NULL,
  type text NOT NULL DEFAULT 'info'::text,
  link text,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Push notification subscriptions
CREATE TABLE IF NOT EXISTS public.push_subscriptions (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL,
  endpoint text NOT NULL,
  p256dh text NOT NULL,
  auth text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  UNIQUE(user_id, endpoint)
);

-- -----------------------------------------------------------------------------
-- 4.7 Settings Table
-- -----------------------------------------------------------------------------

-- Site-wide settings (key-value store)
CREATE TABLE IF NOT EXISTS public.site_settings (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  key text NOT NULL UNIQUE,
  value jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- ============================================================================
-- SECTION 5: INDEXES
-- ============================================================================

-- Profiles indexes
CREATE INDEX IF NOT EXISTS idx_profiles_user_id ON public.profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_profiles_email ON public.profiles(email);

-- User roles indexes
CREATE INDEX IF NOT EXISTS idx_user_roles_user_id ON public.user_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role ON public.user_roles(role);

-- Content articles indexes
CREATE INDEX IF NOT EXISTS idx_content_articles_author_id ON public.content_articles(author_id);
CREATE INDEX IF NOT EXISTS idx_content_articles_slug ON public.content_articles(slug);
CREATE INDEX IF NOT EXISTS idx_content_articles_status ON public.content_articles(status);
CREATE INDEX IF NOT EXISTS idx_content_articles_category ON public.content_articles(category);
CREATE INDEX IF NOT EXISTS idx_content_articles_published_at ON public.content_articles(published_at);
CREATE INDEX IF NOT EXISTS idx_content_articles_created_at ON public.content_articles(created_at);

-- Article images indexes
CREATE INDEX IF NOT EXISTS idx_article_images_article_id ON public.article_images(article_id);
CREATE INDEX IF NOT EXISTS idx_article_images_image_type ON public.article_images(image_type);

-- Article views indexes
CREATE INDEX IF NOT EXISTS idx_article_views_article_id ON public.article_views(article_id);
CREATE INDEX IF NOT EXISTS idx_article_views_viewed_at ON public.article_views(viewed_at);

-- Article likes indexes
CREATE INDEX IF NOT EXISTS idx_article_likes_article_id ON public.article_likes(article_id);

-- Affiliate clicks indexes
CREATE INDEX IF NOT EXISTS idx_affiliate_clicks_article_id ON public.affiliate_banner_clicks(article_id);
CREATE INDEX IF NOT EXISTS idx_affiliate_clicks_clicked_at ON public.affiliate_banner_clicks(clicked_at);

-- Generation history indexes
CREATE INDEX IF NOT EXISTS idx_generation_history_user_id ON public.generation_history(user_id);
CREATE INDEX IF NOT EXISTS idx_generation_history_created_at ON public.generation_history(created_at);

-- Image queue indexes
CREATE INDEX IF NOT EXISTS idx_image_queue_article_id ON public.image_generation_queue(article_id);
CREATE INDEX IF NOT EXISTS idx_image_queue_status ON public.image_generation_queue(status);
CREATE INDEX IF NOT EXISTS idx_image_queue_priority ON public.image_generation_queue(priority);

-- Contact messages indexes
CREATE INDEX IF NOT EXISTS idx_contact_messages_status ON public.contact_messages(status);
CREATE INDEX IF NOT EXISTS idx_contact_messages_created_at ON public.contact_messages(created_at);

-- Contact replies indexes
CREATE INDEX IF NOT EXISTS idx_contact_replies_message_id ON public.contact_message_replies(message_id);

-- Newsletter subscribers indexes
CREATE INDEX IF NOT EXISTS idx_newsletter_subscribers_email ON public.newsletter_subscribers(email);
CREATE INDEX IF NOT EXISTS idx_newsletter_subscribers_is_active ON public.newsletter_subscribers(is_active);

-- Newsletter send history indexes
CREATE INDEX IF NOT EXISTS idx_newsletter_send_history_article_id ON public.newsletter_send_history(article_id);
CREATE INDEX IF NOT EXISTS idx_newsletter_send_history_sent_at ON public.newsletter_send_history(sent_at);

-- Newsletter tracking indexes
CREATE INDEX IF NOT EXISTS idx_newsletter_tracking_send_history_id ON public.newsletter_email_tracking(send_history_id);
CREATE INDEX IF NOT EXISTS idx_newsletter_tracking_token ON public.newsletter_email_tracking(tracking_token);

-- Notifications indexes
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON public.notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON public.notifications(created_at);

-- Audit logs indexes
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON public.audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action_type ON public.audit_logs(action_type);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON public.audit_logs(created_at);

-- Site settings indexes
CREATE INDEX IF NOT EXISTS idx_site_settings_key ON public.site_settings(key);

-- ============================================================================
-- SECTION 6: ROW LEVEL SECURITY (RLS)
-- ============================================================================

-- -----------------------------------------------------------------------------
-- 6.1 Enable RLS on all tables
-- -----------------------------------------------------------------------------

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_articles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.article_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.article_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.article_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.affiliate_banner_clicks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.generation_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.image_generation_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.image_backup_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_message_replies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_reply_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.newsletter_subscribers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.newsletter_send_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.newsletter_email_tracking ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.site_settings ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- 6.2 Profiles Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Users can view own profile" ON public.profiles
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own profile" ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own profile" ON public.profiles
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all profiles" ON public.profiles
  FOR SELECT USING (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can update all profiles" ON public.profiles
  FOR UPDATE USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- -----------------------------------------------------------------------------
-- 6.3 User Roles Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Users can view own role" ON public.user_roles
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all roles" ON public.user_roles
  FOR SELECT USING (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can manage roles" ON public.user_roles
  FOR ALL USING (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can insert roles" ON public.user_roles
  FOR INSERT WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can update roles" ON public.user_roles
  FOR UPDATE USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can delete roles" ON public.user_roles
  FOR DELETE USING (has_role(auth.uid(), 'admin'::app_role));

-- -----------------------------------------------------------------------------
-- 6.4 Audit Logs Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Admins can view audit logs" ON public.audit_logs
  FOR SELECT USING (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can insert audit logs" ON public.audit_logs
  FOR INSERT WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- -----------------------------------------------------------------------------
-- 6.5 Content Articles Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Anyone can view published articles" ON public.content_articles
  FOR SELECT USING (status = 'published' AND published_at IS NOT NULL);

CREATE POLICY "Authors can view own articles" ON public.content_articles
  FOR SELECT USING (author_id IN (SELECT id FROM profiles WHERE user_id = auth.uid()));

CREATE POLICY "Authors can insert own articles" ON public.content_articles
  FOR INSERT WITH CHECK (author_id IN (SELECT id FROM profiles WHERE user_id = auth.uid()));

CREATE POLICY "Authors can update own articles" ON public.content_articles
  FOR UPDATE USING (author_id IN (SELECT id FROM profiles WHERE user_id = auth.uid()));

CREATE POLICY "Authors can delete own articles" ON public.content_articles
  FOR DELETE USING (author_id IN (SELECT id FROM profiles WHERE user_id = auth.uid()));

CREATE POLICY "Admins can manage all articles" ON public.content_articles
  FOR ALL USING (has_role(auth.uid(), 'admin'::app_role));

-- -----------------------------------------------------------------------------
-- 6.6 Article Images Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Anyone can view images of published articles" ON public.article_images
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM content_articles
      WHERE content_articles.id = article_images.article_id
      AND content_articles.status = 'published'
      AND content_articles.published_at IS NOT NULL
    )
  );

CREATE POLICY "Admins can manage all images" ON public.article_images
  FOR ALL USING (is_current_user_admin());

CREATE POLICY "Service role can manage images" ON public.article_images
  FOR ALL USING (auth.role() = 'service_role');

-- -----------------------------------------------------------------------------
-- 6.7 Article Views Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Anyone can read view counts" ON public.article_views
  FOR SELECT USING (true);

CREATE POLICY "Anyone can register views" ON public.article_views
  FOR INSERT WITH CHECK (true);

-- -----------------------------------------------------------------------------
-- 6.8 Article Likes Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Admins can view likes" ON public.article_likes
  FOR SELECT USING (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Anyone can insert likes" ON public.article_likes
  FOR INSERT WITH CHECK (true);

-- -----------------------------------------------------------------------------
-- 6.9 Affiliate Banner Clicks Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Admins can view clicks" ON public.affiliate_banner_clicks
  FOR SELECT USING (is_current_user_admin());

CREATE POLICY "Anyone can register clicks" ON public.affiliate_banner_clicks
  FOR INSERT WITH CHECK (true);

-- -----------------------------------------------------------------------------
-- 6.10 Generation History Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Users can view own history" ON public.generation_history
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own history" ON public.generation_history
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own history" ON public.generation_history
  FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "Admins can manage all history" ON public.generation_history
  FOR ALL USING (has_role(auth.uid(), 'admin'::app_role));

-- -----------------------------------------------------------------------------
-- 6.11 Image Generation Queue Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Admins can manage all queue items" ON public.image_generation_queue
  FOR ALL USING (is_current_user_admin());

CREATE POLICY "Service role bypass for edge functions" ON public.image_generation_queue
  FOR ALL USING (auth.role() = 'service_role');

-- -----------------------------------------------------------------------------
-- 6.12 Image Backup Logs Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Admins can view backup logs" ON public.image_backup_logs
  FOR SELECT USING (is_current_user_admin());

CREATE POLICY "Service role can manage backup logs" ON public.image_backup_logs
  FOR ALL USING (auth.role() = 'service_role');

-- -----------------------------------------------------------------------------
-- 6.13 Contact Messages Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Anyone can submit contact messages" ON public.contact_messages
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Admins can view contact messages" ON public.contact_messages
  FOR SELECT USING (is_current_user_admin());

CREATE POLICY "Admins can update contact messages" ON public.contact_messages
  FOR UPDATE USING (is_current_user_admin());

CREATE POLICY "Admins can delete contact messages" ON public.contact_messages
  FOR DELETE USING (is_current_user_admin());

-- -----------------------------------------------------------------------------
-- 6.14 Contact Message Replies Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Admins can view all replies" ON public.contact_message_replies
  FOR SELECT USING (is_current_user_admin());

CREATE POLICY "Admins can insert replies" ON public.contact_message_replies
  FOR INSERT WITH CHECK (is_current_user_admin());

CREATE POLICY "Service role can manage replies" ON public.contact_message_replies
  FOR ALL USING (auth.role() = 'service_role');

-- -----------------------------------------------------------------------------
-- 6.15 Contact Reply Templates Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Admins can view templates" ON public.contact_reply_templates
  FOR SELECT USING (is_current_user_admin());

CREATE POLICY "Admins can insert templates" ON public.contact_reply_templates
  FOR INSERT WITH CHECK (is_current_user_admin());

CREATE POLICY "Admins can update templates" ON public.contact_reply_templates
  FOR UPDATE USING (is_current_user_admin());

CREATE POLICY "Admins can delete templates" ON public.contact_reply_templates
  FOR DELETE USING (is_current_user_admin());

-- -----------------------------------------------------------------------------
-- 6.16 Newsletter Subscribers Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Anyone can subscribe to newsletter" ON public.newsletter_subscribers
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Admins can view all subscribers" ON public.newsletter_subscribers
  FOR SELECT USING (is_current_user_admin());

CREATE POLICY "Admins can update subscribers" ON public.newsletter_subscribers
  FOR UPDATE USING (is_current_user_admin());

CREATE POLICY "Admins can delete subscribers" ON public.newsletter_subscribers
  FOR DELETE USING (is_current_user_admin());

CREATE POLICY "Service role can manage subscribers" ON public.newsletter_subscribers
  FOR ALL USING (auth.role() = 'service_role');

-- -----------------------------------------------------------------------------
-- 6.17 Newsletter Send History Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Admins can view send history" ON public.newsletter_send_history
  FOR SELECT USING (is_current_user_admin());

CREATE POLICY "Service role can manage send history" ON public.newsletter_send_history
  FOR ALL USING (auth.role() = 'service_role');

-- -----------------------------------------------------------------------------
-- 6.18 Newsletter Email Tracking Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Admins can view email tracking" ON public.newsletter_email_tracking
  FOR SELECT USING (is_current_user_admin());

CREATE POLICY "Service role can manage email tracking" ON public.newsletter_email_tracking
  FOR ALL USING (auth.role() = 'service_role');

-- -----------------------------------------------------------------------------
-- 6.19 Email Templates Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Admins can manage email templates" ON public.email_templates
  FOR ALL USING (is_current_user_admin());

CREATE POLICY "Service role can manage templates" ON public.email_templates
  FOR ALL USING (auth.role() = 'service_role');

-- -----------------------------------------------------------------------------
-- 6.20 Notifications Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Users can view own notifications" ON public.notifications
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can update own notifications" ON public.notifications
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own notifications" ON public.notifications
  FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "Admins can insert notifications" ON public.notifications
  FOR INSERT WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can manage all notifications" ON public.notifications
  FOR ALL USING (has_role(auth.uid(), 'admin'::app_role));

-- -----------------------------------------------------------------------------
-- 6.21 Push Subscriptions Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Users can view own subscriptions" ON public.push_subscriptions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own subscriptions" ON public.push_subscriptions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own subscriptions" ON public.push_subscriptions
  FOR DELETE USING (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- 6.22 Site Settings Policies
-- -----------------------------------------------------------------------------

CREATE POLICY "Admins can view settings" ON public.site_settings
  FOR SELECT USING (is_current_user_admin());

CREATE POLICY "Admins can insert settings" ON public.site_settings
  FOR INSERT WITH CHECK (is_current_user_admin());

CREATE POLICY "Admins can update settings" ON public.site_settings
  FOR UPDATE USING (is_current_user_admin());

CREATE POLICY "Service role can manage settings" ON public.site_settings
  FOR ALL USING (auth.role() = 'service_role');

-- ============================================================================
-- SECTION 7: TRIGGERS
-- ============================================================================

-- Trigger to create profile and assign role when new user signs up
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Triggers for updated_at columns
DROP TRIGGER IF EXISTS update_profiles_updated_at ON public.profiles;
CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_content_articles_updated_at ON public.content_articles;
CREATE TRIGGER update_content_articles_updated_at
  BEFORE UPDATE ON public.content_articles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_contact_messages_updated_at ON public.contact_messages;
CREATE TRIGGER update_contact_messages_updated_at
  BEFORE UPDATE ON public.contact_messages
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_contact_reply_templates_updated_at ON public.contact_reply_templates;
CREATE TRIGGER update_contact_reply_templates_updated_at
  BEFORE UPDATE ON public.contact_reply_templates
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_email_templates_updated_at ON public.email_templates;
CREATE TRIGGER update_email_templates_updated_at
  BEFORE UPDATE ON public.email_templates
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_image_generation_queue_updated_at ON public.image_generation_queue;
CREATE TRIGGER update_image_generation_queue_updated_at
  BEFORE UPDATE ON public.image_generation_queue
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_site_settings_updated_at ON public.site_settings;
CREATE TRIGGER update_site_settings_updated_at
  BEFORE UPDATE ON public.site_settings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================================
-- SECTION 8: STORAGE BUCKETS
-- ============================================================================

-- Note: Storage buckets must be created via Supabase Dashboard or API
-- These are the buckets needed for this project:

-- 1. article-images (PUBLIC)
--    Purpose: Store article cover images and gallery images
--    Public: Yes
--    File size limit: 10MB
--    Allowed mime types: image/jpeg, image/png, image/webp, image/gif

-- 2. avatars (PUBLIC)  
--    Purpose: Store user profile avatars
--    Public: Yes
--    File size limit: 2MB
--    Allowed mime types: image/jpeg, image/png, image/webp

-- 3. article-images-backup (PRIVATE)
--    Purpose: Backup storage for article images
--    Public: No
--    File size limit: 10MB
--    Allowed mime types: image/jpeg, image/png, image/webp, image/gif

-- Storage Policies (execute in Supabase Dashboard):

-- For article-images bucket:
-- CREATE POLICY "Public can view article images"
-- ON storage.objects FOR SELECT
-- USING (bucket_id = 'article-images');

-- CREATE POLICY "Admins can upload article images"
-- ON storage.objects FOR INSERT
-- WITH CHECK (bucket_id = 'article-images' AND is_current_user_admin());

-- CREATE POLICY "Admins can update article images"
-- ON storage.objects FOR UPDATE
-- USING (bucket_id = 'article-images' AND is_current_user_admin());

-- CREATE POLICY "Admins can delete article images"
-- ON storage.objects FOR DELETE
-- USING (bucket_id = 'article-images' AND is_current_user_admin());

-- For avatars bucket:
-- CREATE POLICY "Public can view avatars"
-- ON storage.objects FOR SELECT
-- USING (bucket_id = 'avatars');

-- CREATE POLICY "Users can upload own avatar"
-- ON storage.objects FOR INSERT
-- WITH CHECK (bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1]);

-- CREATE POLICY "Users can update own avatar"
-- ON storage.objects FOR UPDATE
-- USING (bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1]);

-- ============================================================================
-- SECTION 9: CRON JOBS (pg_cron)
-- ============================================================================

-- Schedule image queue processing every 5 minutes
-- Note: This requires pg_cron extension and must be set up in Supabase Dashboard

-- SELECT cron.schedule(
--   'process-image-queue-every-5-min',
--   '*/5 * * * *',
--   $$
--   SELECT net.http_post(
--     url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/process-image-queue',
--     headers := '{"Authorization": "Bearer YOUR_SERVICE_ROLE_KEY"}'::jsonb,
--     body := '{}'::jsonb
--   );
--   $$
-- );

-- ============================================================================
-- SECTION 10: REALTIME SUBSCRIPTIONS
-- ============================================================================

-- Enable realtime for tables that need it
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.image_generation_queue;
ALTER PUBLICATION supabase_realtime ADD TABLE public.contact_messages;

-- ============================================================================
-- SECTION 11: INITIAL DATA (Optional)
-- ============================================================================

-- Insert default email template
INSERT INTO public.email_templates (name, description, category, html_template, is_active, is_default)
VALUES (
  'Default Contact Reply',
  'Template padrão para respostas de contato',
  'contact_reply',
  '<!DOCTYPE html><html><body><h1>Olá {{NAME}}</h1><p>{{CONTENT}}</p></body></html>',
  true,
  true
) ON CONFLICT DO NOTHING;

-- ============================================================================
-- SECTION 12: AUTO GENERATION & COMMEMORATIVE DATES TABLES
-- ============================================================================

-- -----------------------------------------------------------------------------
-- 12.1 Auto Generation Config
-- -----------------------------------------------------------------------------

-- Configuration for automatic article generation (AutoPilot)
CREATE TABLE IF NOT EXISTS public.auto_generation_config (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  enabled boolean NOT NULL DEFAULT false,
  topics jsonb NOT NULL DEFAULT '[]'::jsonb,
  publish_immediately boolean NOT NULL DEFAULT false,
  daily_limit integer NOT NULL DEFAULT 5,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid
);

-- Enable RLS
ALTER TABLE public.auto_generation_config ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Admins can manage auto generation config" 
  ON public.auto_generation_config FOR ALL 
  USING (is_current_user_admin());

CREATE POLICY "Service role can manage config" 
  ON public.auto_generation_config FOR ALL 
  USING (auth.role() = 'service_role');

-- Index
CREATE INDEX IF NOT EXISTS idx_auto_generation_config_enabled ON public.auto_generation_config(enabled);

-- -----------------------------------------------------------------------------
-- 12.2 Auto Generation Logs
-- -----------------------------------------------------------------------------

-- Logs for automatic article generation
CREATE TABLE IF NOT EXISTS public.auto_generation_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  article_id uuid REFERENCES public.content_articles(id) ON DELETE SET NULL,
  topic_used text NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  error_message text,
  executed_at timestamp with time zone NOT NULL DEFAULT now(),
  duration_ms integer
);

-- Enable RLS
ALTER TABLE public.auto_generation_logs ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Admins can view auto generation logs" 
  ON public.auto_generation_logs FOR SELECT 
  USING (is_current_user_admin());

CREATE POLICY "Service role can manage auto generation logs" 
  ON public.auto_generation_logs FOR ALL 
  USING (auth.role() = 'service_role');

-- Indexes
CREATE INDEX IF NOT EXISTS idx_auto_generation_logs_status ON public.auto_generation_logs(status);
CREATE INDEX IF NOT EXISTS idx_auto_generation_logs_executed_at ON public.auto_generation_logs(executed_at);
CREATE INDEX IF NOT EXISTS idx_auto_generation_logs_article_id ON public.auto_generation_logs(article_id);

-- -----------------------------------------------------------------------------
-- 12.3 Auto Generation Schedules
-- -----------------------------------------------------------------------------

-- Schedules for automatic article generation
CREATE TABLE IF NOT EXISTS public.auto_generation_schedules (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  day_of_week integer NOT NULL CHECK (day_of_week >= 0 AND day_of_week <= 6),
  time_slot time without time zone NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.auto_generation_schedules ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Admins can manage auto generation schedules" 
  ON public.auto_generation_schedules FOR ALL 
  USING (is_current_user_admin());

CREATE POLICY "Service role can manage auto generation schedules" 
  ON public.auto_generation_schedules FOR ALL 
  USING (auth.role() = 'service_role');

-- Indexes
CREATE INDEX IF NOT EXISTS idx_auto_generation_schedules_day ON public.auto_generation_schedules(day_of_week);
CREATE INDEX IF NOT EXISTS idx_auto_generation_schedules_active ON public.auto_generation_schedules(is_active);

-- -----------------------------------------------------------------------------
-- 12.4 Commemorative Date Settings
-- -----------------------------------------------------------------------------

-- Settings for commemorative dates (enable/disable specific dates)
CREATE TABLE IF NOT EXISTS public.commemorative_date_settings (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  date_id text NOT NULL UNIQUE,
  is_enabled boolean NOT NULL DEFAULT true,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid
);

-- Enable RLS
ALTER TABLE public.commemorative_date_settings ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Anyone can read commemorative date settings" 
  ON public.commemorative_date_settings FOR SELECT 
  USING (true);

CREATE POLICY "Admins can manage commemorative date settings" 
  ON public.commemorative_date_settings FOR ALL 
  USING (is_current_user_admin());

CREATE POLICY "Service role can manage commemorative date settings" 
  ON public.commemorative_date_settings FOR ALL 
  USING (auth.role() = 'service_role');

-- Indexes
CREATE INDEX IF NOT EXISTS idx_commemorative_date_settings_date_id ON public.commemorative_date_settings(date_id);
CREATE INDEX IF NOT EXISTS idx_commemorative_date_settings_enabled ON public.commemorative_date_settings(is_enabled);

-- Trigger for updated_at
CREATE TRIGGER update_commemorative_date_settings_updated_at
  BEFORE UPDATE ON public.commemorative_date_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================================
-- END OF SCHEMA EXPORT
-- ============================================================================
-- 
-- IMPORTANT NOTES FOR MIGRATION:
-- 
-- 1. Execute this SQL in your Supabase SQL Editor
-- 2. Create storage buckets manually in Supabase Dashboard
-- 3. Set up the following secrets in Edge Functions:
--    - REPLICATE_API_KEY
--    - OPENAI_API_KEY
--    - RESEND_API_KEY
--    - SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD
-- 4. Deploy Edge Functions from supabase/functions directory
-- 5. Configure Auth settings (auto-confirm email, etc.)
-- 6. Set up cron jobs if needed for scheduled tasks
--
-- TABLES TOTAL: 25
-- - profiles, user_roles, audit_logs
-- - content_articles, article_images, article_views, article_likes
-- - affiliate_banner_clicks, generation_history
-- - image_generation_queue, image_backup_logs
-- - contact_messages, contact_message_replies, contact_reply_templates
-- - newsletter_subscribers, newsletter_send_history, newsletter_email_tracking
-- - email_templates, notifications, push_subscriptions
-- - site_settings
-- - auto_generation_config, auto_generation_logs, auto_generation_schedules
-- - commemorative_date_settings
--
-- ============================================================================
