#include <sys/ioctl.h>
#include <stdio.h>
#include <signal.h>
#include <termios.h>
#include <fcntl.h>
#include <sys/time.h>
#include <semaphore.h>
#include <curses.h>
#import <QTKit/QTKit.h>


#define MAX_(x, y) ((x) > (y) ? (x) : (y))
#define MIN_(x, y) ((x) < (y) ? (x) : (y))

sem_t sync_sem;


void syncInit(){sem_init(&sync_sem,0,1);}
void syncStart(){sem_wait(&sync_sem);}
void syncEnd(){sem_post(&sync_sem);}

int WIDTH=0,HEIGHT=0;
int WOFFSET=0;
int HOFFSET=2;
void getWinSize(){
	struct winsize ws;
	ioctl(STDOUT_FILENO,TIOCGWINSZ,&ws);
	WIDTH=ws.ws_col;HEIGHT=ws.ws_row;
}

void cursesInit()
{
	if(!initscr()) {
		printf("Error initializing screen.\n");
		exit(1);
	}
	if(!has_colors()) {
		printf("This terminal does not support colours.\n");
		exit(1);
	}
	use_default_colors();
	start_color();
	nonl();

	for (int i = 0; i <= 255; i++){
		init_pair(i, -1, i);
	}
	curs_set(1);
}

namespace Request{
	bool quit=false;
	bool render=false;
	bool bottom=false;
	bool stop=false;
	bool winsize=false;
}
namespace FrameImage{
	bool colorFlip=false;
	int MAXWIDTH,MAXHEIGHT;
	int originalWidth,originalHeight;
	int* originalData=NULL;
	int* scaledData=NULL;
	int scaledWidth,scaledHeight;

	void init(int maxw,int maxh){
		MAXWIDTH=maxw;MAXHEIGHT=maxh;
		originalWidth=originalHeight=1;
		originalData=new int[MAXWIDTH*MAXHEIGHT];
		scaledData=new int[MAXWIDTH*MAXHEIGHT];
	}
	#define DataRef(arr,x,y) ((arr)[(y)*MAXWIDTH+(x)])
	float getColorAt(float x,float y){
		if(x<0||x>1||y<0||y>1)return 1;
		x=(scaledWidth+1)*x-0.5;
		y=(scaledHeight+1)*y-0.5;
		if(x<0)x=0;if(y<0)y=0;
		int ix=(int)x,iy=(int)y;x-=ix;y-=iy;
		if(ix+1>=scaledWidth){ix=scaledWidth-2;x=1;}
		if(iy+1>=scaledHeight){iy=scaledHeight-2;y=1;}
		return DataRef(scaledData,ix,iy)*(1-x)*(1-y)
					+DataRef(scaledData,ix,iy+1)*(1-x)*y
					+DataRef(scaledData,ix+1,iy)*x*(1-y)
					+DataRef(scaledData,ix+1,iy+1)*x*y;
	}
	inline int getColorAt2(int x,int y){
		return DataRef(scaledData, x, y);
	}
	
	unsigned char hexnaly(unsigned char c)
	{
		unsigned char result = 0;
		double d = c;
		while (d > 0){
			result++;
			d -= (256.0 / 6.0);
		}

		return MAX_(result - 1, 0);
	}

	int hoge=0;
	void update(CVPixelBufferRef img){
		int width=CVPixelBufferGetWidth(img);
		int height=CVPixelBufferGetHeight(img);
		int bytesPerRow=CVPixelBufferGetBytesPerRow(img);
		int bytesPerPixel=bytesPerRow/width;
		CVPixelBufferLockBaseAddress(img,0);
		unsigned char*data=(unsigned char*)CVPixelBufferGetBaseAddress(img);
		unsigned char* rgb;
		#define imgBytesGetRGB(x,y) (data+bytesPerRow*(y)+bytesPerPixel*(x))
		#define imgBytesGet(x,y) (rgb=imgBytesGetRGB(x,y), 16 + (hexnaly(rgb[1]) * 36) + ((hexnaly(rgb[2])) * 6) + hexnaly(rgb[3]))
		//16 +([赤成分(0-5)] x 36) + ([緑成分(0-5)] x 6) + ([青成分(0-5)] x 1)
		//for(int x=0;x<width;x++)for(int y=0;y<height;y++)DataRef(originalData,x,y)=imgBytesGet(x,y);
		for(int x=0;x<width;x++){
			for(int y=0;y<height;y++){
				DataRef(originalData,x,y)=imgBytesGet(x,y);
				//printf("%d %d %d %d\n", imgBytesGet(x, y), hexnaly(rgb[1]), hexnaly(rgb[2]), hexnaly(rgb[3]));
				//printf("%d %d %d %d\n", WIDTH, HEIGHT, scaledWidth, scaledHeight);
			}
		}
		CVPixelBufferUnlockBaseAddress(img,0);
		originalWidth=width;originalHeight=height;
		Request::render=true;
	}
	void scale(){
		int width=originalWidth,height=originalHeight;
		//while((WIDTH-WOFFSET)*2<width||(HEIGHT-HOFFSET)*4<height){width/=2;height/=2;s*=2;}
		/*
		for(int x=0;x<width;x++)for(int y=0;y<height;y++){
			int sum=0;
			//for(int ix=0;ix<s;ix++)for(int iy=0;iy<s;iy++)sum+=DataRef(originalData,s*x+ix,s*y+iy);
			//int col=sum/s/s;
			int col = DataRef(originalData, s * x, s * y);
			DataRef(scaledData,x,y)=colorFlip?1-col:col;
		}*/
		width = (WIDTH - WOFFSET);
		height = (HEIGHT - HOFFSET);
		double off_h, off_w;
		off_h = (double)originalHeight / (double)height;
		off_w = (double)originalWidth / (double)width;
		for (int y = 0; y < height; y++){
			for (int x = 0; x < width; x++){
				/*
				int sum = 0;
				for (int iy = 0; iy < (int)off_h; iy++){
					for (int ix = 0; ix < (int)off_w; ix++){
						sum += DataRef(originalData, MIN_((int)(off_w * x + ix), originalWidth - 1), MIN_((int)(off_h * y + iy), originalHeight - 1));
					}
				}
				*/
				DataRef(scaledData, x, y) = DataRef(originalData, MIN_((int)(off_w * x), originalWidth - 1), MIN_((int)(off_h * y), originalHeight - 1));
				//DataRef(scaledData, x, y) = sum / ((int)off_w * (int)off_h);
			}
		}
		scaledWidth=width;scaledHeight=height;
	}
}

const char*programDirectory(const char*arg0=NULL){
	static char*str;
	if(arg0){
		int len=strlen(arg0);
		str=new char[len+1];
		int endPos=0;
		for(int i=len;i>=0;i--){
			if(!endPos&&arg0[i]=='/')endPos=i+1;
			if(endPos)str[i]=arg0[i];
		}
		str[endPos]=0;
	}
	return str;
}

char charTable[256][256];
void genCharTable(const char*file){
	FILE*fp=fopen(file,"r");
	if(!fp){
		fprintf(stderr,"charInfoFile :%s not found\n",file);
		exit(0);
	}
	char infoChar[256];
	double info[256][2];
	int infoLength=0;
	char line[256];
	while(fgets(line,sizeof(line),fp)){
		if(line[0]&&line[1]==' '){
			int hexup,hexdown;
			int cnt=sscanf(line+2,"%x %x",&hexup,&hexdown);
			if(cnt!=2)continue;
			info[infoLength][0]=hexup;
			info[infoLength][1]=hexdown;
			infoChar[infoLength]=line[0];
			infoLength++;
		}
	}
	fclose(fp);
	double min=0xff;
	for(int i=0;i<infoLength;i++){double av=(info[i][0]+info[i][1])/2.0;if(av<min)min=av;}
	for(int i=0;i<infoLength;i++)for(int j=0;j<2;j++)info[i][j]=0xff*(info[i][j]-min)/(0xff-min);
	for(int i=0;i<256;i++)for(int j=0;j<256;j++){
		double costMin=-1;
		int indexMin=0;
		for(int k=0;k<infoLength;k++){
			double difUp=i-info[k][0],difDown=j-info[k][1],difAv=difUp+difDown;
			double cost=difUp*difUp+difDown*difDown+difAv*difAv*difAv*difAv/1024;
			if(costMin<0||cost<costMin){costMin=cost;indexMin=k;}
		}
		charTable[i][j]=infoChar[indexMin];
	}
}
QTMovie*movie;
float defaultVolume=0.5;
void render();
void showBottom();
namespace IOCTLStatus{
	struct termios tm;
	void setTermios(){
		printf("\x1B%d",7);
		printf("\x1B[?47h\x1B[?1h\x1B=");
		fflush(stdout);
		struct termios t=tm;
		t.c_lflag&=~(ICANON|ECHO);
		tcsetattr(0,TCSANOW,&t);
	}
	void initTermios(){
		tcgetattr(0,&tm);
		setTermios();
	}
	void resetTermios(){
		printf("\x1B[?1l\x1B>\x1B[2J\x1B[?47l");
		printf("\x1B%d\x1B[m\x0D",8);
		fflush(stdout);
		tcsetattr(0,TCSANOW,&tm);
	}
}
void onResume(int n){
	syncStart();
	IOCTLStatus::setTermios();
	syncEnd();
	Request::winsize=true;
	Request::render=true;
}
bool playing;
void onStop(int n){
	Request::stop=true;
}
void onExit(int n){
	Request::quit=true;
}

void onResize(int n){
	Request::winsize=true;
	Request::render=true;
}
void loadSettings(){
	char settingsFile[1024];
	sprintf(settingsFile,"%s%s",programDirectory(),"settings.txt");
	FILE*fp=fopen(settingsFile,"r");
	if(!fp){
		fp=fopen(settingsFile,"w");
		fprintf(fp,"char: [charInfoFile]\nflip: no\nvolume: 0.5\n");
		fclose(fp);
		fprintf(stderr,"settings.txt not found.\nedit the generated settings file.\n");
		exit(0);
	}
	char line[1024];
	while(fgets(line,sizeof(line),fp)){
		for(int i=0;line[i];i++)if(line[i]=='\r'||line[i]=='\n'){line[i]=0;break;}
		char*key=line;
		char*value=0;
		for(int i=0;line[i];i++){if(line[i]==':'){value=line+i+1;line[i]=0;if(value[0]==' ')value++;break;}}
		if(strcmp(key,"char")==0){
			char ctFile[1024];
			sprintf(ctFile,"%s%s",programDirectory(),value);
		}
		if(strcmp(key,"volume")==0)sscanf(value,"%f",&defaultVolume);
		if(strcmp(key,"flip")==0)FrameImage::colorFlip=strcmp(value,"yes")==0;
	}
	fclose(fp);
	
}

namespace INPUT{
	char text[16];
	int index=0;
	void erase(){if(index){text[--index]=0;Request::bottom=true;}}
	void timejump(int t,bool abs=false){
		QTTime time=[movie currentTime];
		QTTime time2=time;
		if(abs)time2.timeValue=t*time.timeScale;
		else time2.timeValue+=t*time.timeScale;
		QTTime duration=[movie duration];
		if(time2.timeValue<0)time2.timeValue=0;
		if(time2.timeValue>duration.timeValue)time2.timeValue=duration.timeValue;
		if(time.timeValue!=time2.timeValue){
			[movie setCurrentTime: time2];
			Request::bottom=true;
		}
	}
	void enter(){
		if(!text[0])return;
		Request::bottom=true;
		if(text[0]=='q'){Request::quit=true;return;}
		if(text[0]=='f'){FrameImage::colorFlip=!FrameImage::colorFlip;text[index=0]=0;Request::render=true;Request::bottom=true;return;}
		if(text[0]=='v'){int v=atoi(text+1);[movie setVolume:(v<0?0:v>100?100:v)/100.];Request::bottom=true;text[index=0]=0;return;}
		int type=0;
		char*str=text;
		if(*str=='+'){type=+1;str++;}
		else if(*str=='-'){type=-1;str++;}
		bool err=false;
		int timearr[3]={0};
		int timeindex=0;
		while(*str){
			char c=*str;
			if('0'<=c&&c<='9')timearr[timeindex]=timearr[timeindex]*10+(c-'0');
			else if(c=='+'||c=='-'){err=true;break;}
			else if(c==':'){timeindex++;if(timeindex==3){err=true;break;}}
			else err=true;
			str++;
		}
		if(!err){
			int sec=0;
			for(int i=0;i<=timeindex;i++)sec=60*sec+timearr[i];
			if(type)timejump(type*sec);
			else timejump(sec,true);
		}
		text[index=0]=0;
	}
	void input(unsigned char c){
		if(c<0x20||c>=0x80)return;
		if(index<(int)sizeof(text)-1){
			text[index++]=c;
			text[index]=0;
			Request::bottom=true;
		}
	}
}


const char*movieFile;
NSSize movieSize;
float volume=0;
QTTime currenttime;
QTTime duration;

void SetNumberValue(CFMutableDictionaryRef dict,CFStringRef key,SInt32 value){
	CFNumberRef numvalue=CFNumberCreate(kCFAllocatorDefault,kCFNumberSInt32Type,&value);
	if(numvalue==NULL)return;
	CFDictionarySetValue(dict,key,numvalue);
	CFRelease(numvalue);
}
QTVisualContextRef CreatePixelBufferContext(int width,int height){
	QTVisualContextRef	  theContext = NULL;
	CFMutableDictionaryRef  pixelBufferOptions = NULL;
	CFMutableDictionaryRef  visualContextOptions = NULL;
	OSStatus				err = noErr;

	// Pixel Buffer attributes
	pixelBufferOptions=CFDictionaryCreateMutable(kCFAllocatorDefault,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
	if (NULL == pixelBufferOptions) {err = coreFoundationUnknownErr; goto bail;}
	SetNumberValue(pixelBufferOptions, kCVPixelBufferPixelFormatTypeKey,k32ARGBPixelFormat);
	SetNumberValue(pixelBufferOptions,kCVPixelBufferWidthKey,width);
	SetNumberValue(pixelBufferOptions,kCVPixelBufferHeightKey,height);
	SetNumberValue(pixelBufferOptions,kCVPixelBufferBytesPerRowAlignmentKey, 16);
	visualContextOptions=CFDictionaryCreateMutable(kCFAllocatorDefault,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
	if (NULL == visualContextOptions) {err = coreFoundationUnknownErr; goto bail; }
	CFDictionarySetValue(visualContextOptions,kQTVisualContextPixelBufferAttributesKey,pixelBufferOptions);
	err = QTPixelBufferContextCreate(kCFAllocatorDefault,visualContextOptions,&theContext);
	if (err != noErr) goto bail;

	return theContext;
	theContext = NULL;
bail:
	if (NULL != visualContextOptions) CFRelease(visualContextOptions);
	if (NULL != pixelBufferOptions) CFRelease(pixelBufferOptions);
	if (NULL != theContext) QTVisualContextRelease(theContext);
	return NULL;
}

void moviecallback(QTVisualContextRef visualContext,const CVTimeStamp *timeStamp,void *refCon){
	QTVisualContextTask(visualContext);
	CVPixelBufferRef img=NULL;
	OSStatus status=QTVisualContextCopyImageForTime(visualContext,kCFAllocatorDefault,timeStamp,&img);
	if(status!=noErr){return;}
	FrameImage::update(img);
	CVPixelBufferRelease(img);
}


int main(int argc,char**argv)
{
	programDirectory(argv[0]);
	loadSettings();
	syncInit();
	
	NSAutoreleasePool*pool=[[NSAutoreleasePool alloc] init];
	movieFile=argc>=2?argv[1]:NULL;
	if(!movieFile||strcmp(movieFile,"-h")==0){
		if(!movieFile)printf("moviefile required.\n");
		printf("usage: aaplayer moviefile\n");
		printf("spaceKey: play/pause\n");
		printf("arrowKeys: move 10 sec\n");
		printf("commads: \n");
		printf("\tq           quit\n");
		printf("\tf           flip color\n");
		printf("\tvXXX        set volume(0-100)\n");
		printf("\tXX:YY:ZZ    set time\n");
		printf("\t+XX:YY:ZZ   move time foreward\n");
		printf("\t-XX:YY:ZZ   move time backward\n");
		return 0;
	}
	NSError*errptr=nil;
	movie = [[QTMovie alloc] initWithFile:[NSString stringWithUTF8String:movieFile] error:&errptr];
	if(errptr){
		fprintf(stderr,"%d: %s\n",(int)[errptr code],[[errptr localizedDescription] UTF8String]);
		return -1;
	}
	
	
	[[movie attributeForKey:QTMovieNaturalSizeAttribute] getValue:&movieSize];
	FrameImage::init(movieSize.width,movieSize.height);
	
	QTVisualContextRef visualContext=CreatePixelBufferContext(movieSize.width,movieSize.height);
	if(visualContext==NULL){fprintf(stderr,"ERROR_PixelBufferContext_Failed\n");return -1;}
	OSStatus status=QTVisualContextSetImageAvailableCallback(visualContext,moviecallback,NULL);
	if(status!=noErr){fprintf(stderr,"ERROR_SetCallBack_Failed\n");return -1;}
	
	freopen("/dev/null","w",stderr);
	
	IOCTLStatus::initTermios();
	signal(SIGWINCH,onResize);
	signal(SIGCONT,onResume);
	signal(SIGTSTP,onStop);
	signal(SIGINT,onExit);
	
	[movie setVisualContext: visualContext];
	[movie setRate:1.0];
	[movie play];playing=true;
	currenttime=[movie currentTime];
	duration=[movie duration];
	[movie setVolume:volume=defaultVolume];
	getWinSize();

	cursesInit();

	render();
	while(true){
		MoviesTask([movie quickTimeMovie],0);
		usleep(1000*1000/20);
		if(Request::stop){
			IOCTLStatus::resetTermios();
			[movie stop];playing=false;
			Request::stop=false;
			raise(SIGSTOP);
		}
		int flag=fcntl(STDIN_FILENO, F_GETFL,0);
		fcntl(STDIN_FILENO, F_SETFL, flag|O_NONBLOCK);
		char c=fgetc(stdin);
		fcntl(STDIN_FILENO, F_SETFL, flag);
		static char escInput[16];
		static int escIndex=0;
		if(escIndex){
			escInput[escIndex++]=c;
			if(escIndex==3){
				if(escInput[1]=='O'){
					if(escInput[2]=='D')INPUT::timejump(-10);
					if(escInput[2]=='C')INPUT::timejump(+10);
				}
				escIndex=0;
			}
		}else if(c==0x1B){
			escInput[escIndex++]=c;
		}else switch(c){
			case ' ':
				if(playing){[movie stop];playing=false;}
				else{[movie play];playing=true;}
				Request::render=true;
				break;
			case '\r':case '\n':INPUT::enter();break;
			case 0x7f:INPUT::erase();break;
			default:INPUT::input(c);
		}
		if(Request::quit){IOCTLStatus::resetTermios();exit(0);}
		currenttime=[movie currentTime];
		duration=[movie duration];
		volume=[movie volume];
		if(currenttime.timeValue==duration.timeValue){playing=false;[movie stop];}
		if(Request::winsize){Request::winsize=false;getWinSize();}
		syncStart();
		if(Request::render)render();
		else if(Request::bottom)showBottom();
		refresh();
		//doupdate();
		syncEnd();
	}
	[pool release];
}

namespace FrameRate{
	double timeSpan=1;
	double framerateIntegral=1;
	timeval lastTime={0,0};
	void setTimeSpan(double t){timeSpan=t;framerateIntegral=1;}
	double getFrameRate(){
		timeval t;
		gettimeofday(&t, NULL);
		double sec=(t.tv_sec-lastTime.tv_sec)+(t.tv_usec-lastTime.tv_usec)/1000000.;
		lastTime=t;
		if(sec<0){framerateIntegral=1;return 0;}
		double decay=exp(-sec/timeSpan);
		framerateIntegral=framerateIntegral*decay+1;
		return -1/log(1-1/framerateIntegral)/timeSpan;
	}
}

void render(){
	Request::render=false;
	FrameImage::scale();
	//printf("\x1B[1;1H\x1B[K\x1B[1m%s  %s  [ %d x %d ]\x1B[m",playing?"playing":"paused ",movieFile,(int)movieSize.width,(int)movieSize.height);
	
	/*
	double w=FrameImage::scaledWidth,h=FrameImage::scaledHeight/2;
	int wof=0,hof=1;
	while((WIDTH-2.0*wof)/HEIGHT-w/h>w/h-(WIDTH-2.0*wof-2)/HEIGHT)wof++;
	while((HEIGHT-2.0*hof)/WIDTH-h/w>h/w-(HEIGHT-2.0*hof-2)/WIDTH)hof++;
	*/
#if 0
	for(int y=0;y<FrameImage::scaledHeight;y++){
		printf("\x1B[%d;1H",y+2);
		for(int x=0;x<FrameImage::scaledWidth;x++){
			int a;
			fprintf(stdout, "\e[48;5;%dm ", a=FrameImage::getColorAt2(x, y));
			/*
			int a=0x100*FrameImage::getColorAt((x+0.5-wof)/(WIDTH-2*wof),(y+0.25-hof)/(HEIGHT-2*hof));
			int b=0x100*FrameImage::getColorAt((x+0.5-wof)/(WIDTH-2*wof),(y+0.75-hof)/(HEIGHT-2*hof));
			putc(charTable[a>0xff?0xff:a][b>0xff?0xff:b],stdout);
			*/
		}
	}
	printf("\x1b[49m");
#else

#define SKIP (1)
	static int  sw = 0;
	for(int y=sw;y<FrameImage::scaledHeight;y += SKIP){
		//printf("\x1B[%d;1H",y+2);
		move(y+1, 1);
		for(int x=0;x<FrameImage::scaledWidth;x++){
			attron(COLOR_PAIR(FrameImage::getColorAt2(x, y)) | A_NORMAL);
			addch(' ');
			//attroff(COLOR_PAIR(FrameImage::getColorAt2(x, y)) | A_NORMAL);
			//printf("\e[48;5;%dm ", a=FrameImage::getColorAt2(x, y));
			/*
			   int a=0x100*FrameImage::getColorAt((x+0.5-wof)/(WIDTH-2*wof),(y+0.25-hof)/(HEIGHT-2*hof));
			   int b=0x100*FrameImage::getColorAt((x+0.5-wof)/(WIDTH-2*wof),(y+0.75-hof)/(HEIGHT-2*hof));
			   putc(charTable[a>0xff?0xff:a][b>0xff?0xff:b],stdout);
			 */
		}
	}
	//printf("\x1b[49m");
	sw = (sw + 1) % SKIP;
#endif
	showBottom();
}
void showBottom(){
	Request::bottom=false;
	/*
	int ctime=currenttime.timeValue/(currenttime.timeScale==0?1:currenttime.timeScale);
	int dtime=duration.timeValue/(duration.timeScale==0?1:duration.timeScale);
	int fr=(int)(10*FrameRate::getFrameRate()+0.5);if(fr>999)fr=999;
	printf("\x1B[%d;1H\x1B[K",HEIGHT);
	printf("\x1B[%d;%dH\x1B[1mfps: %d%d.%d\x1B[m",HEIGHT,WIDTH-10,fr/100,fr/10%10,fr%10);
	printf("\x1B[%d;1H\x1B[1m",HEIGHT);
	int ivol=(int)(volume*100+0.5);
	if(volume==0)printf("volume:muted   ");
	else printf("volume:%3.1d%%    ",ivol<0?0:ivol>100?100:ivol);
	printf("%02d:%02d:%02d / %02d:%02d:%02d",ctime/60/60,ctime/60%60,ctime%60,dtime/60/60,dtime/60%60,dtime%60);
	
	printf("\x1B[m  > %s",INPUT::text);
	*/
}

