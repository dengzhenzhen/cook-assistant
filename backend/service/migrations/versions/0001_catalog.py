"""Initial users, recipes, kitchen, imports, usage and quota schema."""
from alembic import op
import sqlalchemy as sa
revision='0001'
down_revision=None
branch_labels=None
depends_on=None


def upgrade():
    op.create_table('users',sa.Column('id',sa.String(80),primary_key=True),sa.Column('name',sa.String(80),nullable=False))
    op.create_table('recipes',sa.Column('id',sa.String(80),primary_key=True),sa.Column('user_id',sa.String(80),sa.ForeignKey('users.id'),nullable=False),sa.Column('document',sa.JSON(),nullable=False),sa.Column('updated_at',sa.DateTime(timezone=True),nullable=False))
    op.create_index('ix_recipes_user_id','recipes',['user_id'])
    op.create_table('kitchens',sa.Column('id',sa.String(80),primary_key=True),sa.Column('user_id',sa.String(80),sa.ForeignKey('users.id'),nullable=False),sa.Column('document',sa.JSON(),nullable=False),sa.UniqueConstraint('user_id',name='uq_default_kitchen_user'))
    op.create_index('ix_kitchens_user_id','kitchens',['user_id'])
    op.create_table('import_jobs',sa.Column('id',sa.String(80),primary_key=True),sa.Column('user_id',sa.String(80),sa.ForeignKey('users.id'),nullable=False),sa.Column('digest',sa.String(64),nullable=False),sa.Column('status',sa.String(20),nullable=False),sa.Column('payload',sa.JSON(),nullable=False),sa.Column('result',sa.JSON(),nullable=True),sa.Column('error',sa.String(500),nullable=True),sa.Column('created_at',sa.DateTime(timezone=True),nullable=False))
    op.create_index('ix_import_jobs_user_id','import_jobs',['user_id']);op.create_index('ix_import_jobs_digest','import_jobs',['digest'])
    op.create_table('ai_usage',sa.Column('id',sa.String(80),primary_key=True),sa.Column('job_id',sa.String(80),sa.ForeignKey('import_jobs.id'),nullable=False),sa.Column('model',sa.String(100),nullable=False),sa.Column('input_tokens',sa.Integer(),nullable=False),sa.Column('output_tokens',sa.Integer(),nullable=False),sa.Column('created_at',sa.DateTime(timezone=True),nullable=False))
    op.create_index('ix_ai_usage_job_id','ai_usage',['job_id'])
    op.create_table('ai_quotas',sa.Column('key',sa.String(150),primary_key=True),sa.Column('count',sa.Integer(),nullable=False))


def downgrade():
    for name in ['ai_quotas','ai_usage','import_jobs','kitchens','recipes','users']:op.drop_table(name)
