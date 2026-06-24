export interface BlogPost {
    kref: string;
    slug: string;
    title: string;
    author: string;
    date: string;
    content?: string;
    tags: string[];
    revision: string;
    revisions: string[];
    published: boolean;
}

export interface BlogPostCreate {
    title: string;
    author?: string;
    content: string;
    space_path?: string;
    tags?: string[];
}
