# MyBlog - Kumiho SaaS API Demo

A blog application demonstrating how to build a web application using the [Kumiho SaaS API](https://kumiho.io) as a backend.

## Features

- ✅ Create, read, and list blog posts
- ✅ Markdown content support
- ✅ Revision-controlled content storage
- ✅ Hierarchical data organization (Project → Space → Item → Revision)
- ✅ Multi-tenant SaaS architecture
- ✅ Dark mode support
- ✅ Responsive design

## Data Structure

This application uses Kumiho's hierarchical structure:

```
Project: MyBlog
  └─ Space: Tech News
      └─ Sub-space: Kumiho
          └─ Item: [Blog Post Name] (kind: blog-post)
              └─ Revision: r1, r2, ...
                  └─ Metadata:
                      - Title
                      - Author
                      - Date
                      - Content (Markdown)
                      - Tags
```

## Setup

### 1. Get Your Kumiho Token

1. Sign up at [https://kumiho.io](https://kumiho.io)
2. Navigate to your account settings
3. Generate a service token
4. Copy the token

### 2. Configure Environment Variables

Create a `.env.local` file in the project root:

```bash
cp .env.local.example .env.local
```

Edit `.env.local` and add your service token:

```env
KUMIHO_SERVICE_TOKEN=your_actual_token_here
# Deploy your own Kumiho-FastAPI 
NEXT_PUBLIC_API_URL=http://localhost:8001
# or use Kumiho provided FastAPI URL
NEXT_PUBLIC_API_URL=https://api.kumiho.cloud
```

### 3. Start the FastAPI Backend

In a separate terminal, start the Kumiho FastAPI server:

```bash
cd ../kumiho-FastAPI
.venv/Scripts/uvicorn app.main:app --port 8001
```

### 4. Install Dependencies

```bash
npm install
```

### 5. Run the Development Server

```bash
npm run dev
```

Open [http://localhost:3001](http://localhost:3001) in your browser.

## Usage

### Creating a Blog Post

1. Navigate to `/admin/new` or click "New Post" on the home page
2. Fill in the form:
   - **Title**: Your blog post title
   - **Author**: Your name
   - **Content**: Markdown-formatted content
   - **Tags**: Comma-separated tags (optional)
   - **Space Path**: Kumiho hierarchy path (default: `/MyBlog/Tech News/Kumiho`)
3. Click "Create Post"

The post will be created as:
- An **Item** node with kind `blog-post`
- A **Revision** node (`r1`) containing all metadata

### Viewing Posts

- **Home Page** (`/`): Lists all blog posts
- **Post Detail** (`/posts/[slug]`): View full post with markdown rendering

## API Integration

This application uses the Kumiho FastAPI as a backend. The API client is in `lib/kumiho-api.ts`.

### Example API Call

```typescript
import { kumihoApi } from '@/lib/kumiho-api';

// List all posts
const posts = await kumihoApi.listPosts();

// Get a specific post
const post = await kumihoApi.getPost('my-post-slug');

// Create a new post
await kumihoApi.createPost({
  title: 'My Post',
  author: 'John Doe',
  content: '# Hello World',
  tags: ['tutorial'],
});
```

All API calls automatically include the `X-Kumiho-Token` header from your environment variables.

## Project Structure

```
myblog/
├── app/
│   ├── admin/
│   │   ├── new/
│   │   │   └── page.tsx        # Create new post
│   │   └── page.tsx            # Admin dashboard
│   ├── posts/
│   │   └── [slug]/
│   │       └── page.tsx        # Post detail page
│   ├── layout.tsx              # Root layout
│   ├── page.tsx                # Home page (post list)
│   └── globals.css             # Global styles
├── components/
│   ├── Header.tsx              # Site header
│   └── BlogPostCard.tsx        # Post preview card
├── lib/
│   ├── kumiho-api.ts           # API client
│   └── types.ts                # TypeScript types
└── package.json
```

## Tech Stack

- **Framework**: Next.js 15 (App Router)
- **Language**: TypeScript
- **Styling**: Tailwind CSS
- **Markdown**: react-markdown
- **Backend**: Kumiho FastAPI (SaaS API)

## Learn More

- [Kumiho Documentation](https://docs.kumiho.io)
- [FastAPI Deployment Guide](../kumiho-fastAPI/DEPLOYMENT.md)
- [Next.js Documentation](https://nextjs.org/docs)

## License

MIT



