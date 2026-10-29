"""Verify configured DeepSeek credentials without echoing secrets or account data."""
import asyncio
import httpx
from service.config import get_settings

async def main():
    settings=get_settings()
    async with httpx.AsyncClient(timeout=30) as client:
        response=await client.get(settings.deepseek_base_url+'/models',headers={'Authorization':'Bearer '+settings.deepseek_api_key.get_secret_value()})
        print('DeepSeek model endpoint status:',response.status_code)
        if response.status_code==200:
            print('Available models:',', '.join(row['id'] for row in response.json().get('data',[])))
        else:
            raise SystemExit('Credential/connectivity check failed; key omitted.')
asyncio.run(main())
